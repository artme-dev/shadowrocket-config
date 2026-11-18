# Working in shadowrocket-config

Start with [the handoff](docs/HANDOFF.md), then open the relevant profile, guard,
or incident notes. This repository is public.

- Keep account credentials, private subscription and Gist URLs, complete generated
  profiles, raw logs, and screenshots out of Git. Use the ignored `out/` directory
  for local evidence. Keep incident summaries safe to publish.
- The root `artme.conf` is a rules input. The complete personal profile is generated
  under `out/`. Publishing the personal profile and applying it on a device are
  separate from committing source changes. The family subscription is separate.
- Preserve the agreed fixed exit for each AI group and its REJECT fallback. A
  different exit IP is a user decision. Preserve existing DIRECT exceptions.
- Do not stop or restart Shadowrocket's VPN without the user's explicit permission.
  Diagnose with read-only checks or isolated probes first. The watcher can close
  Codex and ChatGPT, so verify live routing and the expected IP before rearming it.
- Check the working tree before generating or publishing. Do not fold unrelated
  local rule changes into an incident or deployment. Validate a candidate in a
  separate ignored output directory and review what differs before publication.
- Record the time, route, target, expected exit, timings and sample count for
  diagnostic results. Attribute a fault only as far as the comparison supports.
