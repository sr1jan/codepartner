import time
import os
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import glob


def setup_logger(
    log_dir: Path, log_name: str, max_size_mb: int = 10, backup_count: int = 5
):
    log_file = log_dir / f"{log_name}.log"

    # Create logger
    logger = logging.getLogger(log_name)
    logger.setLevel(logging.INFO)

    # Create RotatingFileHandler
    handler = RotatingFileHandler(
        log_file,
        maxBytes=max_size_mb * 1024 * 1024,  # Convert MB to bytes
        backupCount=backup_count,
    )

    # Create formatter and add it to the handler
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    handler.setFormatter(formatter)

    # Add the handler to the logger
    logger.addHandler(handler)

    return logger


def cleanup_old_logs(log_dir: Path, log_name: str, keep_days: int = 30):
    current_time = time.time()
    for log_file in glob.glob(str(log_dir / f"{log_name}.log.*")):
        file_time = os.path.getmtime(log_file)
        if (current_time - file_time) // (24 * 3600) >= keep_days:
            os.remove(log_file)
