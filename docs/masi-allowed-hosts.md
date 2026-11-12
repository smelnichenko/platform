# masi: the hosts it may contact

Which hosts masi may reach, the four places that decide it, and why each host of the chart's list is on it. The host
table is held to the list by CI (`.woodpecker/allowed-hosts-doc.sh`): a host in `masiService.http.allowedHosts` that the
table does not name, or a row the list does not hold, fails the build. **Adding or removing a host, or a source that
starts or stops using one: change the list and this table in the same commit.**

## The four layers

| layer | where | what it does | environments |
|---|---|---|---|
| the chart's list `masiService.http.allowedHosts` | platform `helm/schnappy/values.yaml` (rendered as `MASI_HTTP_ALLOWED_HOSTS`) | masi refuses, before DNS, every host not named here - exact names, no suffix match; each refusal is counted per source (alert `MasiSourceHostNotAllowed`) | **test** (`schnappy-test`), and any environment that does not override it |
| production's override | infra `clusters/production/schnappy-production-apps/values.yaml`, `masiService.http.allowedHosts: ["*"]` | any public host: a new source needs no entry (the operator, 2026-10-19; plan 104 PR 1, masi #124 / e0dc51a - an older masi image reads `*` as a literal host) | **production** |
| masi's URL validator | masi `UrlValidator` | refuses internal addresses (private, loopback, link-local, CGNAT) whatever the list says | all |
| the pod's egress policy | platform `helm/schnappy/templates/network-policies.yaml` (masi → public internet) | 80/443 to `0.0.0.0/0` except 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10 | all |

So in production only the last two bound masi; the list below is what **test** may reach. Rows production gained since
2026-10-19 (198 employer feeds, 2026-11-12: Ashby 86, Greenhouse 48, Teamtailor 31, Lever 21, BambooHR 4, others 8) reach
hosts this list mostly does not name - in test such a row is refused and counted.

## The chart's list

| host | used by (source key, or the collector) |
|---|---|
| `cv.ee` | `cvee` - the board's search API |
| `www.cv.ee` | `cvee` - a posting's page |
| `cvpro.ee` | `cvpro` |
| `jobs.kuehne-nagel.com` | `ats:kuehnenagel` |
| `apply.careers.microsoft.com` | `ats:microsoft` (Eightfold) |
| `jobs.ericsson.com` | `ats:ericsson` (Eightfold) |
| `teliacompany.wd3.myworkdayjobs.com` | `ats:telia` (Workday) |
| `www.tootukassa.ee` | `tootukassa` |
| `bolt.eu` | `bolt` |
| `avaandmed.ariregister.rik.ee` | `ariregister`, `ariregisteraruanded`, `ariregisterpeople` - the register's open-data dumps |
| `itl.ee` | `itl` |
| `www.tehnopol.ee` | `tehnopol` |
| `api.smartrecruiters.com` | every `ats:*` row of vendor SmartRecruiters - the collector's API base |
| `boards-api.greenhouse.io` | every `ats:*` row of vendor Greenhouse - the collector's API base |
| `api.lever.co` | every `ats:*` row of vendor Lever - the collector's API base |
| `api.ashbyhq.com` | every `ats:*` row of vendor Ashby - the collector's API base |
| `jobs.swedbank.com` | `ats:swedbank` |
| `luminorbank.teamtailor.com` | `ats:luminor` |
| `starship.teamtailor.com` | `ats:starship` |
| `fractory.teamtailor.com` | `ats:fractory` |
| `comodule.teamtailor.com` | `ats:comodule` |
| `careers.datel.ee` | `ats:datel` |
| `careers.milrem.com` | `ats:milrem` |
| `careers.pactum.com` | `ats:pactum` |
| `www.helmes.com` | `teamdash:helmes` - the employer's site |
| `helmes.teamdash.com` | `teamdash:helmes` - the TeamDash job pages behind it |
| `cyber.ee` | `teamdash:cybernetica` - the employer's site |
| `cyber.teamdash.com` | `teamdash:cybernetica` - the job pages behind it |
| `jobs.bigbank.eu` | `teamdash:bigbank` - the employer's site |
| `bigbank.teamdash.com` | `teamdash:bigbank` - the job pages behind it |
| `www.tehik.ee` | `teamdash:tehik` - the employer's site |
| `tehik.teamdash.com` | `teamdash:tehik` - the job pages behind it |
| `lhv.teamdash.com` | `teamdashlanding:lhv` |
| `sisugroup.teamtailor.com` | `ats:sisugroup` (detected from a MeetFrank apply link, 2026-10-19) |
| `lendurai.teamtailor.com` | `ats:lendurai` (detected from a MeetFrank apply link, 2026-10-19) |
| `apply.workable.com` | every `ats:*` row of vendor Workable - the collector's API base |
| `salv.jobs.personio.de` | `ats:salv` (Personio) |
| `ridango.bamboohr.com` | `ats:ridango` (BambooHR; `ats:cybers`, `ats:piletilevi`, `ats:stebby` are on their own subdomains, not listed) |
| `api.meetfrank.com` | `meetfrank`, `meetfrankpeople` - the public GraphQL API |
| `ncfailid.emta.ee` | `emta` - the Tax and Customs Board's quarterly company figures (a Nextcloud share) |
| `s3.pilw.io` | `places:ee` - the Land and Spatial Development Board's EHAK zips (settlements, municipalities, counties, with boundaries) |
| `download.geonames.org` | `places:ee` - GeoNames' file, for Estonia's former settlement names (its postal codes before the address file) |
| `gisco-services.ec.europa.eu` | `places:eu` - Eurostat's NUTS regions with boundaries (GISCO, © EuroGeographics, non-commercial use) |
| `geoportaal.maaruum.ee` | `addresses:ee` - the Land and Spatial Development Board's official address file (`sihtnumbrid.zip`: every valid address, its postcode and point); `places:ee` - the same file, for each place's postal codes (`addressesUrl`) |
