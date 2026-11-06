"""Execute selected functions from the current EA with test-only MT5 adapters.

This is deliberately not an MQL5 compiler, MT5 emulator or backtesting engine.
No snapshot of production function bodies is stored in the fixtures.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EA_PATH = ROOT / "MeanReversionEA.mq5"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def source():
    return EA_PATH.read_text(encoding="utf-8")


def code_mask(text):
    """Hide comments and literals while preserving offsets and newlines."""
    tokens = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
    return tokens.sub(lambda match: "".join("\n" if c == "\n" else " " for c in match[0]), text)


def balanced_end(mask, opening):
    depth = 0
    for index in range(opening, len(mask)):
        if mask[index] == "{":
            depth += 1
        elif mask[index] == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError("Unbalanced source block")


def function(text, name):
    mask = code_mask(text)
    match = re.search(rf"(?m)^(?:bool|double|int|ulong|datetime|void|string)\s+{re.escape(name)}\s*\(", mask)
    if not match:
        raise ValueError(f"EA function not found: {name}")
    opening = mask.index("{", match.start())
    return text[match.start():balanced_end(mask, opening)]


def structure(text, name):
    mask = code_mask(text)
    match = re.search(rf"(?m)^struct\s+{re.escape(name)}\b", mask)
    if not match:
        raise ValueError(f"EA structure not found: {name}")
    opening = mask.index("{", match.start())
    end = balanced_end(mask, opening)
    semicolon = mask.index(";", end)
    return text[match.start():semicolon + 1]


def declaration(text, name):
    mask = code_mask(text)
    match = re.search(rf"(?m)^(?:const\s+)?\w+\s+{re.escape(name)}\b[^;]*;", mask)
    if not match:
        raise ValueError(f"EA global declaration not found: {name}")
    return text[match.start():match.end()]


def cpp_arrays(text):
    """Adapt MQL dynamic-array declarations to std::vector without altering logic."""
    pattern = r"\b(ulong|long|double|ExitReport|ManagementRetry|DiagnosticPosition|WeeklySession)\s+(\w+\[\](?:\s*,\s*\w+\[\])*)"
    return re.sub(pattern, lambda match: f"std::vector<{match[1]}> {match[2].replace('[]', '')}", text)


def scenario(name, functions, structures=(), declarations=()):
    text = source()
    blocks = [structure(text, item) for item in structures]
    blocks += [declaration(text, item) for item in declarations]
    blocks += [function(text, item) for item in functions]
    return "\n".join([
        (FIXTURES / f"{name}_mock.hpp").read_text(encoding="utf-8"),
        cpp_arrays("\n".join(blocks)),
        (FIXTURES / f"{name}_cases.cpp").read_text(encoding="utf-8"),
    ])


def execute_cpp(program):
    compiler_name = os.environ.get("CXX", "g++")
    compiler = shutil.which(compiler_name)
    if not compiler:
        raise unittest.SkipTest(f"C++17 compiler required: install g++ or set CXX (currently {compiler_name!r})")
    # Every generated source/binary is isolated, allowing parallel runs and cleanup.
    with tempfile.TemporaryDirectory(prefix="mean_reversion_test_") as directory:
        cpp = Path(directory) / "scenario.cpp"
        binary = Path(directory) / "scenario"
        cpp.write_text(program, encoding="utf-8")
        command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                   "-Wno-misleading-indentation", "-I", str(FIXTURES), str(cpp), "-o", str(binary)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(f"Auxiliary C++ compilation failed (not MetaEditor):\n{result.stdout}{result.stderr}")
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(f"Regression assertion failed, exit={result.returncode}:\n{result.stdout}{result.stderr}")
        return result.stdout
