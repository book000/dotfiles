---
paths:
  - "**/*.py"
---

# Python Coding Rules

## Formatting

- Indent with 4 spaces

## Lint

- Code must pass the flake8 error subset:

  ```bash
  flake8 . --count --select=E1,E2,E3,E4,E7,E9,W1,W2,W3,W4,W5,F63,F7,F82 --show-source --statistics
  ```

  Only syntax and logic errors are enforced. Full PEP8 style is not required.

## Documentation

- Write docstrings for all functions and classes. Language: follow the project CLAUDE.md if it specifies one; otherwise Japanese
