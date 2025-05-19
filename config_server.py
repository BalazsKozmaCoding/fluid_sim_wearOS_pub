import http.server
import socketserver
import json
import os
import socket
import threading
import sys
import time

# --- Configuration ---
PORT = 8080
CONFIG_DIR = 'configs'  # Directory containing JSON config files

# --- Shared State ---
# List to hold the names of available JSON config files (without extension)
available_config_names = []
# Name of the currently active configuration
active_config_name = "default" # Default config to serve initially
# Lock to protect access to active_config_name between threads
config_lock = threading.Lock()
# Global variable to hold the server instance for shutdown
httpd_server = None
# Flag to signal server thread to stop
server_should_stop = threading.Event()
# Flag to toggle diagnostic messages
diagnostics_enabled = False

# --- Platform-specific getch ---
try:
    # Windows
    import msvcrt
    def getch():
        if msvcrt.kbhit():
            return msvcrt.getch().decode('utf-8')
        return None
except ImportError:
    # Unix/Linux/macOS
    import tty
    import termios
    def getch():
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno()) # Or tty.setcbreak(fd)
            # Check if there's input available without blocking
            import select
            if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
                ch = sys.stdin.read(1)
                return ch
            return None
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

# --- Configuration Loading ---
def discover_configs():
    """Discovers all .json files in CONFIG_DIR and populates available_config_names."""
    global available_config_names, active_config_name # Ensure active_config_name is global here too
    available_config_names = [] # Reset the list
    if not os.path.isdir(CONFIG_DIR):
        print(f"Error: Configuration directory '{CONFIG_DIR}' not found.")
        return False

    print(f"Loading configurations from '{os.path.abspath(CONFIG_DIR)}':")
    found_configs = []
    for filename in os.listdir(CONFIG_DIR):
        if filename.lower().endswith('.json'):
            config_name = filename[:-5] # Remove .json extension
            # Basic check: just record the name if it ends with .json
            available_config_names.append(config_name)
            # We won't read or validate content here anymore

    if not available_config_names:
        print("No JSON configurations found in directory.")
        return False

    available_config_names.sort() # Sort the list alphabetically
    print(f"  - Discovered: {', '.join(available_config_names)}")

    # Ensure the default exists or set a fallback
    if "default" not in available_config_names:
        if available_config_names: # Check if the list is not empty
             first_available = available_config_names[0]
             print(f"Warning: 'default.json' not found. Using '{first_available}' as default.")
             active_config_name = first_available
        else:
             # This case should be caught by the "No JSON configurations found" check above
             # but as a safeguard:
             print("Error: No configurations found, cannot set a default.")
             active_config_name = None # Indicate no active config possible
             return False # Cannot proceed without configs
    elif active_config_name not in available_config_names:
         # If the previously active config was deleted, reset to default
         print(f"Warning: Previously active config '{active_config_name}' no longer exists. Resetting to 'default'.")
         active_config_name = "default"

    return True

# --- HTTP Handler ---
class ConfigHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        global active_config_name, loaded_configs, config_lock, diagnostics_enabled # Add diagnostics_enabled here

        if self.path.startswith('/config'): # Allow query params like ?timestamp=...
            config_to_serve = None
            # Acquire lock to safely read the active config name
            with config_lock:
                config_to_serve = active_config_name

            if config_to_serve:
                if diagnostics_enabled:
                    print(f"[Handler] Attempting to serve config: {config_to_serve}") # DIAGNOSTIC
                file_path = os.path.join(CONFIG_DIR, f"{config_to_serve}.json")
                config_data = None
                error_message = None

                if not os.path.exists(file_path):
                     error_message = f"Config file not found: {file_path}"
                     print(f"[Handler] Error: {error_message}")
                     self.send_error(404, error_message)
                     return # Stop processing

                try:
                    # Read the file content ON DEMAND
                    with open(file_path, 'r') as f:
                        config_data = f.read()
                    if diagnostics_enabled:
                        print(f"[Handler] Content of {file_path} being served (first 200 chars):\n{config_data[:200]}...") # DIAGNOSTIC
                    # Validate JSON just read
                    json.loads(config_data)
                    if diagnostics_enabled:
                        print(f"[Handler] Successfully read and validated: {file_path}") # DIAGNOSTIC
                except json.JSONDecodeError as e:
                    error_message = f"Invalid JSON in file '{file_path}': {e}"
                    print(f"[Handler] Error: {error_message}")
                    self.send_error(500, error_message)
                    return # Stop processing
                except Exception as e:
                    error_message = f"Error reading file '{file_path}': {e}"
                    print(f"[Handler] Error: {error_message}")
                    self.send_error(500, error_message)
                    return # Stop processing

                # If we got here, config_data should be valid
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                # --- Add Cache-Control headers ---
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.send_header('Pragma', 'no-cache') # HTTP/1.0 backward compatibility
                self.send_header('Expires', '0') # Proxies
                # --- ---
                self.end_headers()
                self.wfile.write(config_data.encode('utf-8'))
            else:
                 # This case should now be less likely with the checks above
                 # but could happen if active_config_name was None initially
                 print("[Handler] Error: No active configuration selected.")
                 self.send_error(500, "No active configuration selected on server.")
        else:
            self.send_error(404, "Not Found. Use /config endpoint.")

    # Optional: Suppress logging for cleaner terminal output
    # def log_message(self, format, *args):
    #     return

# --- Server Thread ---
def run_server():
    """Runs the HTTP server in a separate thread."""
    global httpd_server, server_should_stop
    try:
        with socketserver.TCPServer(("", PORT), ConfigHandler) as httpd:
            httpd_server = httpd # Store server instance for shutdown

            # --- Get local IP address ---
            ip_address = "127.0.0.1" # Default fallback
            try:
                # Try connecting to an external address to find the primary local IP
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.settimeout(0.1) # Prevent long hang if no network
                s.connect(("8.8.8.8", 80)) # Google DNS, doesn't send data
                ip_address = s.getsockname()[0]
                s.close()
            except Exception:
                # Fallback if external connection fails (e.g., offline)
                try:
                    hostname = socket.gethostname()
                    ip_address = socket.gethostbyname(hostname)
                except socket.gaierror:
                     print("Warning: Could not determine local IP address automatically. Using 127.0.0.1.")
            # --- ---

            httpd.timeout = 0.5 # Set timeout for handle_request()
            print(f"Server thread started. Listening on port {PORT}.")
            print(f"Config URL: http://{ip_address}:{PORT}/config") # Print the full URL
            # httpd.serve_forever() # Blocking call, use loop with shutdown check instead
            while not server_should_stop.is_set():
                httpd.handle_request() # Handle one request or timeout
            print("Server thread received stop signal and is exiting.")
    except OSError as e:
         print(f"\nError starting server (port {PORT} likely in use): {e}")
         # Signal main thread to exit if server fails
         server_should_stop.set() # Ensure keyboard loop stops
    except Exception as e:
        print(f"\nServer error: {e}")
        server_should_stop.set()

# --- Keyboard Listener ---
def keyboard_listener():
    """Listens for keyboard input in the main thread to change config."""
    global active_config_name, config_lock, httpd_server, server_should_stop, diagnostics_enabled

    time.sleep(0.5) # Give server thread a moment to start

    while not server_should_stop.is_set(): # Check if server failed
        # Display current status and options
        print("\n---")
        print(f"Serving Config: [ {active_config_name.upper()} ]")
        print("Available configs (Press key to switch):")
        available_keys = {}
        i = 1
        # Iterate over the discovered names list
        for name in available_config_names: # Use the list directly (already sorted)
             key = str(i)
             print(f"  {key}) {name}")
             available_keys[key] = name
             i += 1
        # print("  R) Reload Configs") # Removed Reload option
        print(f"  D) Toggle Diagnostics (Currently: {'ON' if diagnostics_enabled else 'OFF'})")
        print("  Q) Quit")
        print("---")
        print("Enter key: ", end='', flush=True)

        key = None
        while key is None and not server_should_stop.is_set():
             key = getch()
             time.sleep(0.05) # Prevent busy-waiting

        if server_should_stop.is_set():
             break # Exit if server stopped

        key = key.lower() if key else ''

        if key == 'q':
            print("\nQuit signal received.")
            server_should_stop.set()
            if httpd_server:
                 # Important: Signal the server thread to stop
                 print("Signaling server thread to stop...")
                 # Rely on the server_should_stop flag and timeout in run_server loop
                 # threading.Thread(target=httpd_server.shutdown).start() # Removed explicit shutdown call
            break # Exit keyboard loop

        elif key == 'd':
            diagnostics_enabled = not diagnostics_enabled
            print(f"\nDiagnostics {'ENABLED' if diagnostics_enabled else 'DISABLED'}.")
            # No need to re-discover or change active config, just continue loop to show updated menu
            continue

        # Removed 'r' (reload) logic block entirely

        if key in available_keys: # Check if pressed key corresponds to a config number
            new_config_name = available_keys[key]
            with config_lock:
                if new_config_name != active_config_name:
                    print(f"\nSwitching to config: {new_config_name}")
                    active_config_name = new_config_name
                    if diagnostics_enabled:
                        print(f"[Listener] Active config name set to: {active_config_name}") # DIAGNOSTIC
                        # --- Add content preview ---
                        listener_file_path = os.path.join(CONFIG_DIR, f"{active_config_name}.json")
                        try:
                            with open(listener_file_path, 'r') as f:
                                listener_config_data = f.read()
                            # Remove [:200] to show full content
                            print(f"[Listener] Content preview:\n{listener_config_data}") # DIAGNOSTIC
                        except FileNotFoundError:
                            print(f"[Listener] Error: Config file not found at {listener_file_path}") # DIAGNOSTIC
                        except Exception as e:
                            print(f"[Listener] Error reading config file {listener_file_path}: {e}") # DIAGNOSTIC
                        # --- End content preview ---
                else:
                    print(f"\nAlready using config: {new_config_name}")
        elif key and key not in ['q', 'd']: # Avoid printing invalid key for 'q' or 'd'
             print(f"\nInvalid key: '{key}'")

    print("Keyboard listener stopped.")


# --- Main Execution ---
if __name__ == "__main__":
    if not discover_configs(): # Use the renamed function
        sys.exit(1) # Exit if no configs discovered

    # Start the server in a background thread
    server_thread = threading.Thread(target=run_server, daemon=True) # Daemon allows exit if main thread finishes
    server_thread.start()

    # Run the keyboard listener in the main thread
    try:
        keyboard_listener()
    except KeyboardInterrupt:
         print("\nCtrl+C detected. Stopping server...")
         server_should_stop.set()
         if httpd_server:
              # Rely on the server_should_stop flag and timeout in run_server loop
              # threading.Thread(target=httpd_server.shutdown).start() # Removed explicit shutdown call
              pass # Add pass statement as the block cannot be empty
         server_thread.join(timeout=2) # Wait briefly for server thread
         print("Exiting.")
    except Exception as e:
         print(f"\nError in keyboard listener: {e}")
         server_should_stop.set()
         if httpd_server:
              # Rely on the server_should_stop flag and timeout in run_server loop
              # threading.Thread(target=httpd_server.shutdown).start() # Removed explicit shutdown call
              pass # Add pass statement as the block cannot be empty
         server_thread.join(timeout=2) # Also wait here after general exception

    # After keyboard_listener finishes (normally via 'Q' or due to an error/exception)
    # Ensure we wait for the server thread to attempt a clean exit.
    if server_thread.is_alive():
        print("Waiting for server thread to shut down...")
        # The shutdown signal should already be set by keyboard_listener or exception handlers
        server_thread.join(timeout=3) # Wait a bit longer
        if server_thread.is_alive():
            print("Server thread did not exit cleanly after timeout.")
        else:
            print("Server thread exited.")
    print("Exiting main script.")