# Security SLA for dependency vulnerabilities

How many days we have to fix a dependency vulnerability, by severity. The clock starts when the finding is filed as an issue with the `sla-remediation` label, and it's fixed when the pull request that removes it merges. The remediation service reads the block below to set each new finding's due date; changing it only affects findings filed afterwards.

Background is in the issue "Security SLA change: high and critical dependency vulnerabilities must be remediated within 2 days".

```yaml
sla_days:
  critical: 2
  high: 2
  medium: 14
  low: 30
```
