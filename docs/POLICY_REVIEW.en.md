# Policy notes

Review date: November 9, 2026. These notes summarize the [detailed Chinese review](POLICY_REVIEW.md) for the v19 documentation package. They are not Anthropic approval or legal advice. Application code is unchanged from v16.

## Findings and limits

The materials reviewed did not specifically prohibit or authorize this local Desktop multi-instance launch method. The absence of an explicit statement is not enough to establish either a violation or approval. Running a local process with a profile directory should not automatically be equated with scripting requests to the Claude service; the actual implementation and use matter.

The launcher code does not implement credential interception, subscription API requests, request proxying, automatic account rotation, account resale or modifications to the Claude executable. It supplies directory settings when starting the installed official application. Users sign in and interact through that application themselves. This review cannot establish that every user's account access, organization permissions or use complies with the applicable terms.

Owning or switching between authorized accounts is distinct from using accounts to evade limits, bans or safeguards. The tool must not be used for evasion, account sharing or resale. It does not display account email addresses, subscription plans, usage or reset times.

## Official sources and scope

| Source | Relevant scope |
| --- | --- |
| [Consumer Terms of Service](https://www.anthropic.com/legal/consumer-terms), effective October 8, 2025, sections 2 and 3 | Account/credential sharing, non-API automated access, scraping, reverse engineering and circumventing systems or safeguards. The reviewed text does not specifically evaluate this Desktop profile launcher. |
| [Log in to your Claude account](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account) | Native applications, third-party authentication and account switching. Its account-switching instructions do not establish support for this parallel profile method. |
| [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines), effective August 1, 2024 | Permission for branding and avoiding implied affiliation. Local shortcut use and public redistribution are different contexts; this review does not make a trademark infringement determination. |
| [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) | Credential use, third-party sign-in and request routing. Code-specific guidance is not a blanket prohibition or authorization for every Desktop launcher. |
| [Archived Usage Policy](https://www.anthropic.com/legal/archive/22742366-2ef0-4c7a-a833-6523f10d3944), effective September 15, 2025, and the [new policy page](https://www.anthropic.com/legal/aup) | The new page was dated effective November 12, 2026, after the review date. The review did not extract every collapsed section of the older archive. It does not treat the later policy as already effective or claim a complete review of every earlier provision. Recheck the policy effective when publishing or using the tool. |

## Branding and distribution

The name `claude-multi-launcher` / `Claude Multi Launcher` is retained to identify compatibility. Desktop shortcuts use an icon extracted from the user's installed Claude application. The repository does not distribute official icons or use them as the project logo, and it contains no Claude binaries, user configuration or credentials.

The README clearly identifies this as an unofficial community tool. That notice and the project's MIT license do not grant rights to Anthropic's trademarks or software. No specific branding authorization has been established, and that fact alone is not presented here as a finding of infringement.

The user chose to retain the name and local shortcut icon. Obtaining written permission or changing the name/icon is not a prerequisite imposed by this packaging task. If Anthropic provides a specific requirement or the applicable terms change, reassess the implementation and documentation accordingly. This package does not claim official approval or guaranteed compliance and has not been uploaded to GitHub by this task.

## What the demo proves

The GIF uses the real launcher HTML with mock backend responses and sample profile names. It demonstrates UI steps, not real Claude sign-in, isolation or process behavior. The launcher-generated loopback access token is separate from Claude authentication. Real Windows acceptance items remain listed in [CURRENT_STATE.md](dev/CURRENT_STATE.md).
