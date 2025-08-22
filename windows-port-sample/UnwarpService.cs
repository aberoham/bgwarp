using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;
using System.Management;
using System.Runtime.InteropServices;

namespace Unwarp.Windows
{
    /// <summary>
    /// Windows Service implementation of unwarp
    /// Runs as SYSTEM and handles privileged WARP disconnection operations
    /// </summary>
    public partial class UnwarpService : ServiceBase
    {
        private const string PIPE_NAME = "UnwarpServicePipe";
        private const string EVENT_LOG_SOURCE = "unwarp";
        private const string WARP_CLI_PATH = @"C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe";
        
        private EventLog _eventLog;
        private Thread _pipeServerThread;
        private bool _stopping = false;
        private readonly Random _random = new Random();

        public UnwarpService()
        {
            ServiceName = "UnwarpEmergencyService";
            InitializeEventLog();
        }

        protected override void OnStart(string[] args)
        {
            LogMessage("Unwarp service starting...");
            
            // Start named pipe server on background thread
            _pipeServerThread = new Thread(PipeServerLoop)
            {
                IsBackground = true,
                Name = "UnwarpPipeServer"
            };
            _pipeServerThread.Start();
            
            LogMessage("Unwarp service started successfully");
        }

        protected override void OnStop()
        {
            LogMessage("Unwarp service stopping...");
            _stopping = true;
            
            // Wait for pipe server to stop
            if (_pipeServerThread != null && _pipeServerThread.IsAlive)
            {
                _pipeServerThread.Join(5000);
            }
            
            LogMessage("Unwarp service stopped");
        }

        private void InitializeEventLog()
        {
            if (!EventLog.SourceExists(EVENT_LOG_SOURCE))
            {
                EventLog.CreateEventSource(EVENT_LOG_SOURCE, "Application");
            }
            
            _eventLog = new EventLog("Application");
            _eventLog.Source = EVENT_LOG_SOURCE;
        }

        private void LogMessage(string message, EventLogEntryType type = EventLogEntryType.Information)
        {
            try
            {
                _eventLog?.WriteEntry($"{DateTime.Now:yyyy-MM-dd HH:mm:ss} - {message}", type);
            }
            catch
            {
                // Fail silently if logging fails
            }
        }

        private void PipeServerLoop()
        {
            var pipeSecurity = new PipeSecurity();
            
            // Allow Administrators and SYSTEM full control
            pipeSecurity.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                PipeAccessRights.FullControl,
                AccessControlType.Allow));
            
            pipeSecurity.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                PipeAccessRights.FullControl,
                AccessControlType.Allow));

            while (!_stopping)
            {
                try
                {
                    using (var pipeServer = new NamedPipeServerStream(
                        PIPE_NAME,
                        PipeDirection.InOut,
                        1,
                        PipeTransmissionMode.Message,
                        PipeOptions.None,
                        1024,
                        1024,
                        pipeSecurity))
                    {
                        LogMessage("Waiting for client connection...");
                        pipeServer.WaitForConnection();

                        using (var reader = new StreamReader(pipeServer))
                        using (var writer = new StreamWriter(pipeServer) { AutoFlush = true })
                        {
                            var command = reader.ReadLine();
                            LogMessage($"Received command: {command}");

                            switch (command)
                            {
                                case "DISCONNECT":
                                    var result = PerformEmergencyDisconnect();
                                    writer.WriteLine(result ? "SUCCESS" : "FAILED");
                                    break;
                                    
                                case "STATUS":
                                    writer.WriteLine("READY");
                                    break;
                                    
                                default:
                                    writer.WriteLine("INVALID_COMMAND");
                                    break;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    LogMessage($"Pipe server error: {ex.Message}", EventLogEntryType.Error);
                    Thread.Sleep(1000); // Brief pause before retry
                }
            }
        }

        private bool PerformEmergencyDisconnect()
        {
            try
            {
                LogMessage("Starting WARP emergency disconnect...", EventLogEntryType.Warning);
                
                // Step 1: Disconnect WARP via CLI
                if (!ExecuteWarpDisconnect())
                {
                    LogMessage("WARP CLI disconnect failed, continuing anyway...", EventLogEntryType.Warning);
                }
                
                // Step 2: Forcefully terminate WARP processes
                TerminateWarpProcesses();
                
                // Step 3: Network recovery operations
                PerformNetworkRecovery();
                
                // Step 4: Schedule auto-recovery
                int reconnectBaseSeconds = GetReconnectTime();
                ScheduleAutoRecovery(reconnectBaseSeconds);
                
                LogMessage("WARP emergency disconnect completed successfully");
                return true;
            }
            catch (Exception ex)
            {
                LogMessage($"Emergency disconnect failed: {ex.Message}", EventLogEntryType.Error);
                return false;
            }
        }

        private bool ExecuteWarpDisconnect()
        {
            try
            {
                if (!File.Exists(WARP_CLI_PATH))
                {
                    LogMessage($"warp-cli not found at {WARP_CLI_PATH}", EventLogEntryType.Warning);
                    return false;
                }

                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = WARP_CLI_PATH,
                        Arguments = "disconnect",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                bool exited = process.WaitForExit(10000); // 10 second timeout
                
                if (!exited)
                {
                    process.Kill();
                    return false;
                }

                return process.ExitCode == 0;
            }
            catch (Exception ex)
            {
                LogMessage($"Failed to execute warp-cli: {ex.Message}", EventLogEntryType.Error);
                return false;
            }
        }

        private void TerminateWarpProcesses()
        {
            string[] processNames = { 
                "Cloudflare WARP",
                "CloudflareWARP",
                "warp-svc",
                "warp-taskbar"
            };

            foreach (var processName in processNames)
            {
                try
                {
                    var processes = Process.GetProcessesByName(processName);
                    foreach (var process in processes)
                    {
                        try
                        {
                            LogMessage($"Terminating process: {processName} (PID: {process.Id})");
                            process.Kill();
                            process.WaitForExit(5000);
                            process.Dispose();
                        }
                        catch (Exception ex)
                        {
                            LogMessage($"Failed to kill {processName}: {ex.Message}", EventLogEntryType.Warning);
                        }
                    }
                }
                catch (Exception ex)
                {
                    LogMessage($"Error finding process {processName}: {ex.Message}", EventLogEntryType.Warning);
                }
            }
        }

        private void PerformNetworkRecovery()
        {
            LogMessage("Starting network recovery operations...");

            // Flush DNS cache
            ExecuteCommand("ipconfig", "/flushdns");
            
            // Reset network routes (dangerous but sometimes necessary)
            // ExecuteCommand("route", "-f"); // Commented out as it's very disruptive
            
            // Restart DNS Client service
            try
            {
                RestartService("Dnscache");
            }
            catch (Exception ex)
            {
                LogMessage($"Failed to restart DNS service: {ex.Message}", EventLogEntryType.Warning);
            }

            // Reset network adapters via WMI
            try
            {
                ResetNetworkAdapters();
            }
            catch (Exception ex)
            {
                LogMessage($"Failed to reset network adapters: {ex.Message}", EventLogEntryType.Warning);
            }
        }

        private void RestartService(string serviceName)
        {
            using (var service = new ServiceController(serviceName))
            {
                if (service.Status == ServiceControllerStatus.Running)
                {
                    service.Stop();
                    service.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(30));
                }
                
                service.Start();
                service.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(30));
            }
        }

        private void ResetNetworkAdapters()
        {
            using (var searcher = new ManagementObjectSearcher(
                "SELECT * FROM Win32_NetworkAdapter WHERE NetConnectionStatus = 2"))
            {
                foreach (ManagementObject adapter in searcher.Get())
                {
                    var name = adapter["Name"]?.ToString() ?? "Unknown";
                    LogMessage($"Resetting network adapter: {name}");
                    
                    try
                    {
                        adapter.InvokeMethod("Disable", null);
                        Thread.Sleep(2000);
                        adapter.InvokeMethod("Enable", null);
                    }
                    catch (Exception ex)
                    {
                        LogMessage($"Failed to reset adapter {name}: {ex.Message}", EventLogEntryType.Warning);
                    }
                }
            }
        }

        private void ExecuteCommand(string command, string arguments)
        {
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = command,
                        Arguments = arguments,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    }
                };

                process.Start();
                process.WaitForExit(10000); // 10 second timeout
            }
            catch (Exception ex)
            {
                LogMessage($"Failed to execute {command} {arguments}: {ex.Message}", EventLogEntryType.Warning);
            }
        }

        private int GetReconnectTime()
        {
            try
            {
                using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\unwarp"))
                {
                    if (key != null)
                    {
                        var value = key.GetValue("ReconnectBaseSeconds");
                        if (value != null && int.TryParse(value.ToString(), out int seconds))
                        {
                            return Math.Max(60, Math.Min(43200, seconds));
                        }
                    }
                }
            }
            catch { }
            
            return 7200; // Default 2 hours
        }

        private void ScheduleAutoRecovery(int baseSeconds)
        {
            // Random delay between base and 2x base
            int randomDelay = baseSeconds + _random.Next(baseSeconds + 1);
            var triggerTime = DateTime.Now.AddSeconds(randomDelay);
            
            LogMessage($"Scheduling auto-recovery in {randomDelay} seconds (at {triggerTime:yyyy-MM-dd HH:mm:ss})");

            try
            {
                // Create scheduled task for reconnection
                var taskName = $"UnwarpRecovery_{Process.GetCurrentProcess().Id}_{DateTime.Now.Ticks}";
                var xml = $@"<?xml version=""1.0"" encoding=""UTF-16""?>
<Task version=""1.2"" xmlns=""http://schemas.microsoft.com/windows/2004/02/mit/task"">
  <RegistrationInfo>
    <Description>Unwarp auto-recovery task - reconnects WARP after emergency disconnect</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>{triggerTime:yyyy-MM-ddTHH:mm:ss}</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <DeleteExpiredTaskAfter>PT1M</DeleteExpiredTaskAfter>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context=""Author"">
    <Exec>
      <Command>{WARP_CLI_PATH}</Command>
      <Arguments>connect</Arguments>
    </Exec>
    <Exec>
      <Command>schtasks.exe</Command>
      <Arguments>/delete /tn ""{taskName}"" /f</Arguments>
    </Exec>
  </Actions>
</Task>";

                // Save XML to temp file
                var tempFile = Path.GetTempFileName();
                File.WriteAllText(tempFile, xml);

                // Register the task
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "schtasks.exe",
                        Arguments = $"/create /tn \"{taskName}\" /xml \"{tempFile}\" /f",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                process.WaitForExit();

                // Clean up temp file
                try { File.Delete(tempFile); } catch { }

                if (process.ExitCode == 0)
                {
                    LogMessage($"Auto-recovery task scheduled successfully: {taskName}");
                }
                else
                {
                    LogMessage($"Failed to schedule auto-recovery task, exit code: {process.ExitCode}", 
                        EventLogEntryType.Warning);
                }
            }
            catch (Exception ex)
            {
                LogMessage($"Failed to schedule auto-recovery: {ex.Message}", EventLogEntryType.Error);
            }
        }

        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();
    }
}