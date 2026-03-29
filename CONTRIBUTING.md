# Contributing

Thank you for contributing! Please follow the project's guidelines.

## Local linting

Run the checks locally before pushing:

```sh
# Install recommended tools (non-privileged)
# shellcheck: https://github.com/koalaman/shellcheck
# shfmt: https://github.com/mvdan/sh

# Check shell scripts with ShellCheck
shellcheck modules/*.sh main.sh

# Check formatting with shfmt (diff mode)
shfmt -d -s -i 2 modules/*.sh main.sh

# To apply formatting locally:
shfmt -w -s -i 2 modules/*.sh main.sh
```
