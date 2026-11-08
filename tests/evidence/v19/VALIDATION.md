# v19 English demo validation

Date: November 9, 2026.

- Playwright + Edge interacted with the actual launcher HTML using English i18n strings. Two mock create requests and two mock launch requests succeeded; no page errors, real Claude process, account data access or external requests. See english-demo-checks.json.
- The English GIF was decoded frame by frame: 68 frames, 1040×790, 28.96 seconds, 498916 bytes, looping. See english-gif-checks.json. Creation, first-launch notice and end-card frames were visually inspected; captions and controls are readable with no overlap.
- README.md embeds the English animation. README.zh-CN.md retains the Chinese animation. Navigation links, English policy links and packaged local links are verified.
- Program/UI files and existing tests are compared byte for byte with v18 and remain unchanged. The v16 core/feature/visual test evidence is historical evidence, not tests re-run for this documentation update.
- Run check_docs.py before packaging; require 0 ERROR / 0 WARN. Check ZIP CRC, source bytes, UTF-8 BOM, runtime equality, README/media inclusion and exclusion of local account data or Claude binaries/icons.
- M1 / M3 remain pending user acceptance. Actual sign-in, isolation, process lifecycle and large-folder Recycle Bin behavior are not established by the demo.
