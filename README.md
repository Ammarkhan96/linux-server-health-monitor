# Linux Server Health Monitoring Toolkit

A Bash-based Linux system monitoring tool that checks CPU utilization,
memory utilization, filesystem disk usage, and system load. It produces
timestamped reports, records execution logs, detects threshold violations,
and can run automatically using cron.

## Project Objectives

- Practise Linux administration and Bash scripting.
- Monitor system resource utilization.
- Configure thresholds without editing the main script.
- Generate timestamped health reports.
- Automate recurring checks with cron.
- Validate behavior through automated tests.
- Use Git and GitHub to document a practical DevOps project.

## Technologies

- Ubuntu Linux
- Bash
- Linux `/proc` filesystem
- `awk`, `df`, `free` utilities and standard Linux commands
- cron
- Git and GitHub

## Architecture

```text
Linux Server
    |
    v
Cron Scheduler (every 5 minutes)
    |
    v
scripts/monitor.sh
    |
    +---- config/monitor.conf
    |
    +---- CPU measurement (/proc/stat)
    |
    +---- Memory measurement (/proc/meminfo)
    |
    +---- Disk measurement (df)
    |
    +---- System load (/proc/loadavg)
    |
    +---- logs/monitor.log
    |
    +---- reports/health-YYYY-MM-DD.log
