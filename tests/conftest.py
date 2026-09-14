import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(root), str(root / "control")]
