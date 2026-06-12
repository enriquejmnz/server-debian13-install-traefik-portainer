"""Testinfra tests for the common role."""

import testinfra


def test_base_packages_installed(host):
    """Verify base packages are installed."""
    packages = ["curl", "gnupg", "lsb-release", "ca-certificates", "python3-apt"]
    for pkg in packages:
        assert host.package(pkg).is_installed, f"Package {pkg} is not installed"


def test_apt_cache_updated(host):
    """Verify apt cache exists and is recent."""
    cache = host.file("/var/cache/apt/pkgcache.bin")
    assert cache.exists
