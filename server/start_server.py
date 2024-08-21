import os
import sys
import subprocess
from pathlib import Path
from log_utils import setup_logger, cleanup_old_logs
import threading

SERVER_DIR = Path(__file__).parent
# Setup logging
logger = setup_logger(SERVER_DIR, "codepartner_server", max_size_mb=10, backup_count=5)


def log_output(process, logger):
    while True:
        line = process.stdout.readline()
        if not line and process.poll() is not None:
            break
        if line:
            logger.info(line.strip())


def run_server():
    api_key = os.environ.get("CODEPARTNER_API_KEY")
    if not api_key:
        print("Error: CODEPARTNER_API_KEY environment variable is not set.")
        sys.exit(1)

    app_path = SERVER_DIR / "app.py"

    # Cleanup old logs
    cleanup_old_logs(SERVER_DIR, "codepartner_server", keep_days=30)

    pid_file = SERVER_DIR / "codepartner_server.pid"

    process = subprocess.Popen(
        [sys.executable, str(app_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=str(SERVER_DIR),
        env=dict(os.environ, CODEPARTNER_API_KEY=api_key),
        start_new_session=True,
        bufsize=1,
        universal_newlines=True,
    )

    # Write PID to file
    with open(pid_file, "w") as f:
        f.write(str(process.pid))

    # Start logging in a separate thread
    log_thread = threading.Thread(target=log_output, args=(process, logger))
    log_thread.start()

    logger.info(f"CodePartner server started with PID {process.pid}")

    return process, log_thread


def monitor_server(process, log_thread):
    try:
        process.wait()
    finally:
        log_thread.join(timeout=5)  # Wait for logging thread to finish
        if log_thread.is_alive():
            logger.warning(
                "Logging thread did not finish. It may be forcefully terminated."
            )


if __name__ == "__main__":
    process, log_thread = run_server()
    monitor_server(process, log_thread)
