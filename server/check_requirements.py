import sys
import pkg_resources
import subprocess
from pathlib import Path


def check_requirements():
    server_dir = Path(__file__).parent
    req_path = server_dir / "requirements.txt"
    with open(req_path, "r") as f:
        requirements = f.read().splitlines()

    # Check which packages are missing
    missing = []
    for requirement in requirements:
        try:
            pkg_resources.require(requirement)
        except pkg_resources.DistributionNotFound:
            missing.append(requirement)

    return missing


def install_requirements(missing):
    for package in missing:
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])


if __name__ == "__main__":
    missing = check_requirements()
    if missing:
        print(f"Missing packages: {', '.join(missing)}")
        sys.exit(1)
    else:
        print("All requirements are satisfied.")
        sys.exit(0)
