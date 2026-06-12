"""Testinfra tests for the security role.

Note: Some services (UFW, auditd, fail2ban runtime, systemd-timesyncd)
do not function in Docker containers. These tests verify FILE CONFIGURATION
only, not service state.
"""

import testinfra


def debian_major_version(host):
    """Return Debian major version from /etc/os-release."""
    return int(host.check_output(". /etc/os-release && printf '%s' \"$VERSION_ID\"").split(".", 1)[0])


def test_security_packages_installed(host):
    """Verify core security packages are installed."""
    packages = ["ufw", "fail2ban", "unattended-upgrades", "sudo"]
    for pkg in packages:
        assert host.package(pkg).is_installed, f"Package {pkg} is not installed"


def test_sshd_config_deployed(host):
    """Verify sshd_config contains hardening directives."""
    f = host.file("/etc/ssh/sshd_config")
    assert f.exists
    assert f.contains("PermitRootLogin no")
    assert f.contains("PasswordAuthentication no")
    assert f.contains("AllowGroups sshusers")


def test_sshd_config_permissions(host):
    """Verify sshd_config has correct permissions."""
    f = host.file("/etc/ssh/sshd_config")
    assert f.exists
    assert f.mode == 0o644


def test_fail2ban_jail_local(host):
    """Verify fail2ban jail.local is deployed with systemd backend."""
    f = host.file("/etc/fail2ban/jail.local")
    assert f.exists
    assert f.contains("[sshd]")
    assert f.contains("backend = systemd")


def test_fail2ban_paths_debian(host):
    """Verify fail2ban path override is only applied on Debian 13."""
    f = host.file("/etc/fail2ban/paths-debian.conf")
    if debian_major_version(host) >= 13:
        assert f.exists
        assert f.contains("sshd_backend = systemd")


def test_openssh_server_installed(host):
    """Verify OpenSSH server is installed for sshd validation."""
    assert host.package("openssh-server").is_installed


def test_limits_conf(host):
    """Verify system limits configuration includes nofile and nproc."""
    f = host.file("/etc/security/limits.conf")
    assert f.exists
    assert f.contains("nofile")
    assert f.contains("nproc")


def test_systemd_limits(host):
    """Verify systemd-level limits are configured."""
    f = host.file("/etc/systemd/system.conf.d/limits.conf")
    assert f.exists
    assert f.contains("DefaultLimitNOFILE")
    assert f.contains("DefaultLimitNPROC")


def test_systemd_limits_directory(host):
    """Verify systemd conf.d directory exists."""
    d = host.file("/etc/systemd/system.conf.d")
    assert d.exists
    assert d.is_directory


def test_unattended_upgrades_config(host):
    """Verify unattended-upgrades custom config is deployed."""
    f = host.file("/etc/apt/apt.conf.d/50unattended-upgrades-custom")
    assert f.exists
    assert f.contains("Automatic-Reboot")


def test_sshusers_group_exists(host):
    """Verify sshusers group was created."""
    assert host.group("sshusers").exists


def test_admin_user_created(host):
    """Verify admin user exists with correct group memberships."""
    user = host.user("testadmin")
    assert user.exists
    assert "sudo" in user.groups
    assert "sshusers" in user.groups


def test_sudoers_file(host):
    """Verify sudoers drop-in file exists with correct permissions."""
    # The role creates /etc/sudoers.d/admin-user (not per-username)
    f = host.file("/etc/sudoers.d/admin-user")
    assert f.exists
    assert f.mode == 0o440


def test_sudoers_content(host):
    """Verify sudoers file grants correct privileges."""
    f = host.file("/etc/sudoers.d/admin-user")
    assert f.exists
    assert f.contains("testadmin")
    assert f.contains("NOPASSWD")


def test_timezone_set(host):
    """Verify timezone is set to UTC."""
    f = host.file("/etc/timezone")
    assert f.exists
    assert f.content.strip() == b"UTC"
