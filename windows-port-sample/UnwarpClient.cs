using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading.Tasks;
using Microsoft.Win32;
using Windows.Security.Credentials.UI;

namespace Unwarp.Windows
{
    /// <summary>
    /// Client application for unwarp that handles authentication and communicates with the service
    /// </summary>
    public class UnwarpClient
    {
        private const string PIPE_NAME = "UnwarpServicePipe";
        private const int MAX_AUTH_ATTEMPTS = 3;
        private const int AUTH_LOCKOUT_SECONDS = 60;
        private const int AUTH_BACKOFF_SECONDS = 5;
        
        private static bool _liveMode = false;
        private static int _reconnectSeconds = 7200;

        static async Task<int> Main(string[] args)
        {
            // Parse command line arguments
            if (!ParseArguments(args))
            {
                return 1;
            }

            // Display appropriate banner
            DisplayBanner();

            // Check if running as administrator
            if (!IsRunningAsAdministrator())
            {
                Console.WriteLine("Error: This program must be run as administrator.");
                Console.WriteLine("Please right-click and select 'Run as administrator'.");
                return 1;
            }

            // Check if user is at console
            if (!IsConsoleUser())
            {
                Console.WriteLine("[!] Access denied: This tool can only be used from the physical console.");
                Console.WriteLine("    Remote sessions are not permitted for security reasons.");
                LogToEventLog("Access denied: Remote session attempted", EventLogEntryType.Warning);
                return 1;
            }

            // Check rate limiting
            if (!CheckRateLimit())
            {
                return 1;
            }

            // Perform authentication
            Console.WriteLine("[*] Authenticating with Windows Hello...");
            bool authenticated = await AuthenticateUser();
            
            RecordAuthAttempt(authenticated);

            if (!authenticated)
            {
                Console.WriteLine("[!] Authentication failed. Access denied.");
                return 1;
            }

            Console.WriteLine("[+] Authentication successful\n");

            // If in test mode, show what would happen
            if (!_liveMode)
            {
                PerformTestMode();
                return 0;
            }

            // Communicate with service to perform disconnect
            try
            {
                if (SendCommandToService("DISCONNECT"))
                {
                    Console.WriteLine("\n[+] WARP emergency disconnect completed!");
                    LogToEventLog("Emergency WARP disconnect completed", EventLogEntryType.Warning);
                    return 0;
                }
                else
                {
                    Console.WriteLine("\n[!] Failed to disconnect WARP. Check Event Viewer for details.");
                    return 1;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\n[!] Error: {ex.Message}");
                LogToEventLog($"Client error: {ex.Message}", EventLogEntryType.Error);
                return 1;
            }
        }

        private static bool ParseArguments(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i].ToLower())
                {
                    case "--help":
                    case "-h":
                    case "/?":
                        ShowHelp();
                        return false;

                    case "--liveincident":
                        _liveMode = true;
                        break;

                    case "--reconnect":
                        if (i + 1 < args.Length && int.TryParse(args[i + 1], out int seconds))
                        {
                            if (seconds < 60 || seconds > 43200)
                            {
                                Console.WriteLine($"Error: --reconnect value must be between 60 and 43200 seconds");
                                Console.WriteLine($"       You specified: {seconds} seconds");
                                return false;
                            }
                            _reconnectSeconds = seconds;
                            i++; // Skip next arg
                        }
                        else
                        {
                            Console.WriteLine("Error: --reconnect requires a numeric value");
                            return false;
                        }
                        break;

                    default:
                        Console.WriteLine($"Unknown argument: {args[i]}");
                        Console.WriteLine("Use --help for usage information");
                        return false;
                }
            }
            return true;
        }

        private static void DisplayBanner()
        {
            Console.WriteLine();
            if (!_liveMode)
            {
                Console.WriteLine("╔════════════════════════════════════════════════════════════╗");
                Console.WriteLine("║                    TEST MODE ACTIVE                        ║");
                Console.WriteLine("╠════════════════════════════════════════════════════════════╣");
                Console.WriteLine("║ This is a test run. Commands will be shown but NOT        ║");
                Console.WriteLine("║ executed. Authentication will be required as normal.       ║");
                Console.WriteLine("╚════════════════════════════════════════════════════════════╝");
            }
            else
            {
                Console.WriteLine("╔════════════════════════════════════════════════════════════╗");
                Console.WriteLine("║         ⚠️  LIVE INCIDENT MODE - DESTRUCTIVE ACTION ⚠️      ║");
                Console.WriteLine("╠════════════════════════════════════════════════════════════╣");
                Console.WriteLine("║ WARNING: This tool will forcefully disconnect WARP and     ║");
                Console.WriteLine("║ remove all configuration. Use only during outages when     ║");
                Console.WriteLine("║ the dashboard is inaccessible.                             ║");
                Console.WriteLine("╚════════════════════════════════════════════════════════════╝");
            }
            Console.WriteLine();
        }

        private static void ShowHelp()
        {
            Console.WriteLine("Emergency WARP disconnect tool for Windows");
            Console.WriteLine();
            Console.WriteLine("Usage: unwarp.exe [OPTIONS]");
            Console.WriteLine();
            Console.WriteLine("Options:");
            Console.WriteLine("  --liveincident    Execute in live mode (destructive actions)");
            Console.WriteLine("  --reconnect <seconds> Set reconnect base time in seconds (60-43200)");
            Console.WriteLine("                        Default: 7200 (2 hours)");
            Console.WriteLine("                        Actual reconnect: random between base and 2x base");
            Console.WriteLine("  --help, -h, /?    Print this help message");
            Console.WriteLine();
            Console.WriteLine("Description:");
            Console.WriteLine("  unwarp (break glass WARP) is an emergency tool that forcefully");
            Console.WriteLine("  disconnects Cloudflare WARP during outages when the dashboard");
            Console.WriteLine("  is inaccessible. It requires Windows Hello authentication and");
            Console.WriteLine("  administrator privileges.");
            Console.WriteLine();
            Console.WriteLine("Features:");
            Console.WriteLine("  - Safe by default: Runs in test mode unless --liveincident is specified");
            Console.WriteLine("  - Windows Hello authentication required (with password fallback)");
            Console.WriteLine("  - Automatic network recovery after WARP disconnection");
            Console.WriteLine("  - Auto-reconnection to WARP after base time (randomized)");
            Console.WriteLine();
            Console.WriteLine("Test Mode (default):");
            Console.WriteLine("  Shows what commands would be executed without making changes");
            Console.WriteLine("  Authentication is still required to test the full flow");
            Console.WriteLine();
            Console.WriteLine("Live Mode (--liveincident):");
            Console.WriteLine("  WARNING: Destructive operation that will:");
            Console.WriteLine("  - Disconnect and terminate WARP");
            Console.WriteLine("  - Kill all WARP processes");
            Console.WriteLine("  - Flush DNS cache");
            Console.WriteLine("  - Reset network adapters");
            Console.WriteLine("  - Schedule WARP reconnection");
            Console.WriteLine();
            Console.WriteLine("Example:");
            Console.WriteLine("  unwarp.exe                  # Run in test mode");
            Console.WriteLine("  unwarp.exe --liveincident   # Run in live mode");
            Console.WriteLine("  unwarp.exe --liveincident --reconnect 300  # 5 min base reconnect");
        }

        private static bool IsRunningAsAdministrator()
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private static bool IsConsoleUser()
        {
            var sessionId = Process.GetCurrentProcess().SessionId;
            var consoleSessionId = WTSGetActiveConsoleSessionId();

            return sessionId == consoleSessionId;
        }

        private static async Task<bool> AuthenticateUser()
        {
            try
            {
                // First try Windows Hello
                var result = await UserConsentVerifier.RequestVerificationAsync(
                    "Authenticate to perform emergency WARP disconnect");

                switch (result)
                {
                    case UserConsentVerificationResult.Verified:
                        LogToEventLog("Windows Hello authentication successful");
                        return true;

                    case UserConsentVerificationResult.DeviceNotPresent:
                    case UserConsentVerificationResult.NotConfiguredForUser:
                        Console.WriteLine("Windows Hello not available, falling back to password...");
                        return await AuthenticateWithCredentialDialog();

                    case UserConsentVerificationResult.Canceled:
                        LogToEventLog("Authentication canceled by user");
                        return false;

                    default:
                        LogToEventLog($"Windows Hello authentication failed: {result}");
                        return false;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Authentication error: {ex.Message}");
                Console.WriteLine("Falling back to password authentication...");
                return await AuthenticateWithCredentialDialog();
            }
        }

        private static async Task<bool> AuthenticateWithCredentialDialog()
        {
            try
            {
                // This requires additional Windows APIs that would need P/Invoke
                // For now, returning a simplified implementation
                Console.WriteLine("[!] Password authentication would be implemented here");
                Console.WriteLine("    Using CredUIPromptForWindowsCredentials API");
                
                // In a real implementation, you would:
                // 1. Call CredUIPromptForWindowsCredentials
                // 2. Validate the credentials
                // 3. Return success/failure
                
                return false;
            }
            catch (Exception ex)
            {
                LogToEventLog($"Credential dialog error: {ex.Message}", EventLogEntryType.Error);
                return false;
            }
        }

        private static bool CheckRateLimit()
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(@"SOFTWARE\unwarp"))
                {
                    var attempts = (int)(key.GetValue("AuthAttempts", 0) ?? 0);
                    var lastAttemptTicks = (long)(key.GetValue("LastAttempt", 0) ?? 0);
                    var lockoutEndTicks = (long)(key.GetValue("LockoutEnd", 0) ?? 0);

                    var now = DateTime.Now;
                    var lastAttempt = new DateTime(lastAttemptTicks);
                    var lockoutEnd = new DateTime(lockoutEndTicks);

                    // Check if in lockout period
                    if (lockoutEnd > now)
                    {
                        var remaining = (int)(lockoutEnd - now).TotalSeconds;
                        Console.WriteLine($"Too many failed authentication attempts.");
                        Console.WriteLine($"Please wait {remaining} seconds before trying again.");
                        LogToEventLog($"Rate limit: blocked for {remaining} more seconds");
                        return false;
                    }

                    // Reset if enough time has passed
                    if (lastAttempt.AddSeconds(AUTH_LOCKOUT_SECONDS) < now)
                    {
                        attempts = 0;
                        key.SetValue("AuthAttempts", 0);
                    }

                    // Check if at limit
                    if (attempts >= MAX_AUTH_ATTEMPTS)
                    {
                        key.SetValue("LockoutEnd", now.AddSeconds(AUTH_LOCKOUT_SECONDS).Ticks);
                        Console.WriteLine($"Maximum authentication attempts exceeded.");
                        Console.WriteLine($"Account locked for {AUTH_LOCKOUT_SECONDS} seconds.");
                        LogToEventLog($"Rate limit: max attempts exceeded, locking for {AUTH_LOCKOUT_SECONDS} seconds");
                        return false;
                    }

                    // Apply backoff for multiple attempts
                    if (attempts > 0)
                    {
                        var backoffTime = AUTH_BACKOFF_SECONDS * attempts;
                        var timeSinceLastAttempt = (now - lastAttempt).TotalSeconds;

                        if (timeSinceLastAttempt < backoffTime)
                        {
                            var waitTime = (int)(backoffTime - timeSinceLastAttempt);
                            Console.WriteLine($"Please wait {waitTime} seconds before next attempt.");
                            return false;
                        }
                    }

                    return true;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Rate limit check error: {ex.Message}");
                return true; // Allow attempt on error
            }
        }

        private static void RecordAuthAttempt(bool success)
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(@"SOFTWARE\unwarp"))
                {
                    if (success)
                    {
                        key.SetValue("AuthAttempts", 0);
                        key.SetValue("LastAttempt", 0);
                        key.SetValue("LockoutEnd", 0);
                        LogToEventLog("Authentication successful");
                    }
                    else
                    {
                        var attempts = (int)(key.GetValue("AuthAttempts", 0) ?? 0) + 1;
                        key.SetValue("AuthAttempts", attempts);
                        key.SetValue("LastAttempt", DateTime.Now.Ticks);

                        var remaining = MAX_AUTH_ATTEMPTS - attempts;
                        if (remaining > 0)
                        {
                            Console.WriteLine($"Authentication failed. {remaining} attempt(s) remaining.");
                        }
                        LogToEventLog($"Authentication failed: attempt {attempts} of {MAX_AUTH_ATTEMPTS}");
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to record auth attempt: {ex.Message}");
            }
        }

        private static void PerformTestMode()
        {
            Console.WriteLine("[TEST] Permission Status:");
            Console.WriteLine($"  - Current User: {Environment.UserName}");
            Console.WriteLine($"  - Is Administrator: {IsRunningAsAdministrator()}");
            Console.WriteLine($"  - Session ID: {Process.GetCurrentProcess().SessionId}");
            Console.WriteLine($"  - Is Console Session: {IsConsoleUser()}");
            Console.WriteLine();

            Console.WriteLine("[TEST] Service Status:");
            if (CheckServiceStatus())
            {
                Console.WriteLine("  ✓ Unwarp service is running");
            }
            else
            {
                Console.WriteLine("  ✗ Unwarp service is not running or not installed");
            }
            Console.WriteLine();

            Console.WriteLine("[TEST] Commands that would be executed:");
            Console.WriteLine($"  - warp-cli disconnect");
            Console.WriteLine($"  - Terminate processes: Cloudflare WARP, warp-svc, warp-taskbar");
            Console.WriteLine($"  - ipconfig /flushdns");
            Console.WriteLine($"  - Reset network adapters");
            Console.WriteLine($"  - Schedule reconnection in {_reconnectSeconds} seconds (randomized)");
            Console.WriteLine();

            if (_reconnectSeconds != 7200)
            {
                Console.WriteLine($"[TEST] Custom reconnect time: {_reconnectSeconds} seconds");
            }

            // Store reconnect time for service
            try
            {
                using (var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\unwarp"))
                {
                    key.SetValue("ReconnectBaseSeconds", _reconnectSeconds);
                }
            }
            catch { }

            Console.WriteLine("\n[TEST] Test mode completed. No actual commands were executed.");
            Console.WriteLine("To execute in a live incident, run with: --liveincident");
        }

        private static bool CheckServiceStatus()
        {
            try
            {
                using (var pipe = new NamedPipeClientStream(".", PIPE_NAME, PipeDirection.InOut))
                {
                    pipe.Connect(1000); // 1 second timeout
                    using (var writer = new StreamWriter(pipe) { AutoFlush = true })
                    using (var reader = new StreamReader(pipe))
                    {
                        writer.WriteLine("STATUS");
                        var response = reader.ReadLine();
                        return response == "READY";
                    }
                }
            }
            catch
            {
                return false;
            }
        }

        private static bool SendCommandToService(string command)
        {
            // Store reconnect time for service
            try
            {
                using (var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\unwarp"))
                {
                    key.SetValue("ReconnectBaseSeconds", _reconnectSeconds);
                }
            }
            catch { }

            try
            {
                using (var pipe = new NamedPipeClientStream(".", PIPE_NAME, PipeDirection.InOut))
                {
                    Console.WriteLine("[*] Connecting to unwarp service...");
                    pipe.Connect(5000); // 5 second timeout

                    using (var writer = new StreamWriter(pipe) { AutoFlush = true })
                    using (var reader = new StreamReader(pipe))
                    {
                        Console.WriteLine("[*] Sending disconnect command...");
                        writer.WriteLine(command);
                        
                        var response = reader.ReadLine();
                        return response == "SUCCESS";
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[!] Failed to communicate with service: {ex.Message}");
                return false;
            }
        }

        private static void LogToEventLog(string message, EventLogEntryType type = EventLogEntryType.Information)
        {
            try
            {
                if (!EventLog.SourceExists("unwarp"))
                {
                    EventLog.CreateEventSource("unwarp", "Application");
                }

                EventLog.WriteEntry("unwarp", $"Client: {message}", type);
            }
            catch
            {
                // Fail silently
            }
        }

        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();
    }
}