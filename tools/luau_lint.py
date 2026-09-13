#!/usr/bin/env python3
"""
luau_lint.py -- catches the class of corruption that `rojo build` cannot.

WHY THIS EXISTS
    `rojo build` does NOT parse Luau. It packages files into a .rbxl and reports success on
    source that Roblox will refuse to compile. That is not a hypothetical: a stray carriage
    return was once written into the middle of a `--` comment in Bootstrap.client.luau, which
    ended the comment early and turned the rest of the line into code:

        Bootstrap:2295: Expected identifier when parsing expression, got '9v'

    Bootstrap builds the entire HUD, so that one byte removed every GUI in the game -- and
    `rojo build` had reported "Built project" the whole time.

WHAT IT CHECKS (a real lexer for strings/comments, not a regex)
    * control characters, and bare CR not part of a CRLF -- either can split a comment or a
      string and silently turn prose into code
    * unterminated string literals
    * unterminated long strings / long comments  [[ ... ]]

WHAT IT DOES NOT CHECK
    Grammar. It is a lexer, not a parser -- it will not catch a missing `end` or a bad
    expression. Roblox Studio's own compile is still the final word. This exists to catch
    ENCODING damage, which is the failure mode tooling here is blind to.

USAGE
    python tools/luau_lint.py            # lint src/ and tools/
    python tools/luau_lint.py <paths...>
    exit code 0 = clean, 1 = problems found
"""

import glob
import io
import sys

LONG_OPEN = "[["


def lint(path):
    """Return a list of (line, message) problems for one file."""
    data = io.open(path, "rb").read()
    problems = []

    # ---- byte-level: control characters and bare CR ----
    for i, b in enumerate(data):
        nxt = data[i + 1] if i + 1 < len(data) else None
        bare_cr = (b == 0x0D and nxt != 0x0A)
        ctrl = (b < 0x09) or b in (0x0B, 0x0C)
        if bare_cr or ctrl:
            line = data[:i].count(b"\n") + 1
            what = "bare CR (not CRLF)" if bare_cr else "control character"
            problems.append((line, f"{what} 0x{b:02x} -- this can end a comment or string early"))

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        problems.append((0, f"file is not valid UTF-8: {e}"))
        return problems

    # ---- lex: walk the file tracking strings and comments ----
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]

        if c == "\n":
            line += 1
            i += 1
            continue

        # long comment / long string:  --[[ ]]  or  [[ ]]  (with optional = padding)
        if text.startswith("--", i):
            j = i + 2
            if j < n and text[j] == "[":
                k = j + 1
                while k < n and text[k] == "=":
                    k += 1
                if k < n and text[k] == "[":
                    close = "]" + "=" * (k - j - 1) + "]"
                    end = text.find(close, k + 1)
                    if end == -1:
                        problems.append((line, "unterminated long comment --[[ ..."))
                        break
                    line += text.count("\n", i, end)
                    i = end + len(close)
                    continue
            # ordinary line comment: runs to end of line
            end = text.find("\n", i)
            i = n if end == -1 else end
            continue

        if c == "[":
            k = i + 1
            while k < n and text[k] == "=":
                k += 1
            if k < n and text[k] == "[" and k > i:
                close = "]" + "=" * (k - i - 1) + "]"
                end = text.find(close, k + 1)
                if end == -1:
                    problems.append((line, "unterminated long string [[ ..."))
                    break
                line += text.count("\n", i, end)
                i = end + len(close)
                continue

        if c in "\"'":
            quote, j, closed = c, i + 1, False
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == "\n":
                    break                      # a newline inside a short string is illegal
                if text[j] == quote:
                    closed = True
                    break
                j += 1
            if not closed:
                problems.append((line, f"unterminated {quote} string"))
                end = text.find("\n", i)
                i = n if end == -1 else end
                continue
            i = j + 1
            continue

        i += 1

    return problems


def main(argv):
    paths = argv[1:]
    if not paths:
        paths = sorted(
            glob.glob("src/**/*.luau", recursive=True)
            + glob.glob("tools/**/*.luau", recursive=True)
        )

    total, files = 0, 0
    for p in paths:
        found = lint(p)
        if found:
            files += 1
            total += len(found)
            print(p)
            for line, msg in found:
                print(f"  line {line}: {msg}")

    if total:
        print(f"\nFAIL -- {total} problem(s) in {files} file(s)")
        return 1
    print(f"OK -- {len(paths)} file(s) lexed clean "
          "(encoding + strings + comments; NOT a grammar check)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
