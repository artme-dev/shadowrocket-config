# Handoff for the next session

## What this setup is for

OpenAI and Claude should keep their assigned ISP exit as the first-hop VPN changes.
The user wants to keep and renew that address, including during recovery where the
provider can preserve it. They prefer a temporary outage to an automatic IP change.
Ordinary proxied traffic uses the first-hop VPN alone. Existing DIRECT rules apply.
The Mac and iPhone use one personal Shadowrocket profile. The family receives a
separate servers-only subscription.

## Where to work

| Item | Location |
| --- | --- |
| Desired entries, priority and ISP mapping | [personal/artme.json](../personal/artme.json) |
| Base rules and personal build | [artme.conf](../artme.conf), [personal profile guide](../personal/README.md) |
| Build and semantic checks | [assemble_artme.py](../tools/assemble_artme.py), [validate_artme.py](../tools/validate_artme.py) |
| Watcher and PF kill switch | [mac-guards](../mac-guards/README.md) |
| Read-only Mac status app | [AI Network](../mac-status/README.md) |
| Acceptance tests and design history | [Network lab](network-lab/README.md) |
| Operational incidents | [Incident index](incidents/README.md) |

The generated personal profile, its subscription URL and credentials live in
ignored local files. Get the publication target from `personal/publish.local.json`
and the URL from `out/artme-url.txt`. The default output file is `out/artme.conf`.
Keep these on the Mac or in a private transfer if moving to a different machine.
A session on this same workspace can read them directly. Subscription refresh is
manual, as agreed.

## Current state recorded on 18 November 2026

- The last verified personal publication was the 11 November AUTO priority
  change in `8e39e9d`. Amsterdam and Almaty lead the fallback order. AUTO tests
  entry reachability and does not measure latency through the complete ISP chain.
- The current IPRoyal incident is [documented separately](incidents/2026-11-18-iproyal.md).
  Support has requested alternate-port tests and a configuration screenshot.
  The conversation has no confirmed repair or confirmation that the screenshot
  was sent.
- Shadowrocket was connected. The last screen inspection showed **Global
  Routing = Proxy** with a Blanc New York node. Personal rules require **Config**.
  Recheck the live settings before interpreting AI exit tests.
- The watcher `com.local.ai-watch` was explicitly disabled and unloaded at the
  user's request. The user reported disabling the kill switch during diagnosis.
  On recheck, `com.local.artme-ai-guard` was registered and enabled in launchd.
  That verifies job registration only. Live PF enforcement was not audited.
  Treat guard rearming as a distinct operation after verifying the AI route.
- At handoff creation, the working tree had a separate local DIRECT edit for
  DeepSeek and OpenCode in the base `artme.conf`, and an untracked ISP probe.
  Neither was bundled with the handoff. Recheck before rebuilding or publishing.

Continue by comparing the current IPRoyal port with the recorded baseline. If
support repairs the node, use fresh checks through the actual personal Config on
Mac and iPhone to verify the original exit and practical response times. Verify
voice separately from HTTPS and only then review rearming the Mac protection.
