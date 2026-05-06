# SmartctlWearHigh

**Severity:** warning · **For:** 1h

## What fired

`smartctl_device_percentage_used{device="$labels.device"} > 80` — the drive's wear indicator is over 80%. NVMe spec: 100% means the drive has reached its rated endurance (TBW). Past 100% the drive may continue working but reliability declines.

## Impact

Drive nearing end of rated life. Not a failure yet, but plan replacement before the wear hits 100% and definitely before drive starts failing self-tests.

## First steps

```bash
ssh ten 'sudo smartctl -a /dev/${labels_device}' | grep -E 'Percentage Used|Data Units|Power On Hours'
```

Estimate remaining life:
- Samsung 980 PRO 1TB: 600 TBW rated
- 1% wear ≈ 6 TBW
- Daily write rate (`Data Units Written` delta over 24h) → days until 100%

## Mitigation

- Plan replacement at 90%, no later than 95%.
- Keep an eye on `SmartctlDeviceFailing` and `SmartctlMediaErrors` — these usually start firing as wear climbs into the >95% range.
