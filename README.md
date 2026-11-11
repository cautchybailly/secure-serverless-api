# Zero-Bypass Secure Serverless API

![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC) ![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900) ![Cognito](https://img.shields.io/badge/Auth-Cognito%20MFA-DD344C) ![Lambda](https://img.shields.io/badge/Lambda-Python%20%C2%B7%20Node-FF9900) ![Source](https://img.shields.io/badge/source-private%20·%20on%20request-lightgrey)

## Overview
A request arrives. The WAF decides whether it's hostile, Cognito decides who's asking, and the Lambda decides what that caller can touch. Meanwhile a scheduled detector notices tokens that were issued but never used, and Bedrock writes a SOC-analyst read on what the WAF saw.

Each layer fails with its own response on purpose. When something comes back 403, you can tell *which* layer said no without opening a log.

```
Internet ─► AWS WAF ─────────── AWS managed common rule set + rate limit (100 req / 5 min / IP) → 403
         ─► API Gateway REST (v1) ─ Cognito user pool authorizer, MFA required → 401
              /python  (GET)   any authenticated group
              /node    (GET)   admins only   → RBAC enforced in Lambda → 403
              /analyze (POST)  admins only   → waf-bedrock-analyzer
WAF logs (authorization + cookie headers redacted) ─► CloudWatch ─► analyzer ─► DynamoDB waf-events + Bedrock SOC summary
Token telemetry ─► DynamoDB token-tracking ─► EventBridge rate(5 min) ─► unused-token detector ─► Bedrock ─► SNS
```

Everything is Terraform except the two things that shouldn't be: Cognito users with permanent passwords, and Bedrock model access.

### What it proves
| Capability | How |
|---|---|
| Layered edge defense | A regional WAFv2 on the REST stage. Every route sits behind it, with no path to the origin that skips it |
| Identity | Cognito user pool with **MFA required** (TOTP + SMS) and a Cognito authorizer on all three methods |
| RBAC done right | `cognito:groups` normalized to a real list before the membership check, so `admins-readonly` can't pass for `admins`. See [`samples/get_groups.py`](samples/get_groups.py) |
| Telemetry that can't break requests | Token usage is recorded in DynamoDB, and failures are logged and swallowed so they never fail the request |
| Detection | A detector runs every 5 minutes, is timezone-aware, paginates its scans, and alerts once per token instead of every run |
| AI-assisted analysis | Bedrock (Claude 3 Haiku) summarizes WAF events and detector alerts |
| Credential hygiene | WAF logs redact `authorization` and `cookie`, so the logs don't quietly become a token store. See [`samples/waf_logging_redaction.tf`](samples/waf_logging_redaction.tf) |
| Least privilege | One IAM role per function, scoped to its own tables, log groups and the single Bedrock model it needs. The analyzer can't publish to SNS, and the API handlers can't call Bedrock |

## Requirements
Terraform ≥ 1.x, AWS CLI v2, Python 3.13 and Node.js 22 (Lambda runtimes), and an AWS account with Bedrock access for Claude 3 Haiku.

## Folder structure
The full private repo:
```
provider.tf  variables.tf  outputs.tf  terraform.tfvars.example
apigateway.tf  waf.tf  cognito.tf  iam.tf  cloudwatch.tf
lambda-python.tf  lambda-node.tf  lambda-analyzer.tf  lambda-detector.tf
dynamodb.tf  eventbridge.tf  bedrock.tf  sns.tf
src/{python,node,analyzer,detector}/   scripts/{get_token.py, verify.sh, verify_groups.py}
```
Public here: this README, `samples/` and `artifacts/`.

## Deployment steps (summary)
1. `terraform init` → `plan` → `apply`
2. Create an admin user and a student user, then get tokens with `scripts/get_token.py`
3. Run the four-way test:
   - **401** with no token: the authorizer stops it, so the Lambda never runs
   - **200** with any valid token on `/python`
   - **403** as a student on `/node`, from RBAC in the Lambda; **200** as an admin
   - **403** for an XSS payload: the WAF blocks it before auth even runs
4. `scripts/verify.sh` checks three things in order: the resources exist, they're **wired together**, and they **behave**

## Engineering decisions
- **Verify the wiring, not just the existence.** A Web ACL that exists but isn't associated with the stage bills you every month to inspect zero traffic. `verify.sh` checks the association, the logging, the redaction and the Bedrock reachability.
- **REST v1 on purpose,** for the Cognito user-pool authorizer and the WAF association on the stage.
- **Redeploy on change.** The API deployment is keyed to a hash over the routing and auth config, so changes actually ship.
- **18 defects in the reference code were engineered out**, each with a comment at the fix site. They include a DynamoDB reserved word (`used`), a Lambda with no handler, the wrong WAF log ARN format, an unauthenticated `/analyze` route, unpaginated scans, and naive datetimes. The full table is in the private README.

## Artifacts
*Capture these on the next deploy:*
| # | Evidence |
|---|---|
| 1 | `terraform apply` complete |
| 2 | Web ACL: allowed vs. blocked |
| 3 | Sampled request showing the blocked XSS payload and the rule that caught it |
| 4 | The 401 / 200 / 403 / 403 matrix, side by side |
| 5 | User pool: MFA required, both groups |
| 6 | `BEDROCK SOC SUMMARY` in the analyzer logs |
| 7 | Detector alert with the AI summary |
| 8 | `verify.sh` all-pass output |

## Teardown
`terraform destroy`, then delete the hand-made Cognito users if the pool persists.

## Code access
The full source is private. I can do a live walkthrough or grant time-limited read access for a technical review. Email cautchy@proton.me.

## References
- Amazon Web Services. (2026). *Amazon API Gateway developer guide*. https://docs.aws.amazon.com/apigateway/
- Amazon Web Services. (2026). *Amazon Cognito developer guide*. https://docs.aws.amazon.com/cognito/
- Amazon Web Services. (2026). *AWS WAF developer guide*. https://docs.aws.amazon.com/waf/
- Built on the BalericaAI lambda curriculum (lessons b–h), hardened and extended.

## Troubleshooting
| Response | Which layer | Meaning |
|---|---|---|
| 403 with no token needed | WAF | The request looked hostile |
| 401 | Cognito authorizer | Missing or expired token |
| 403 with a valid token | Lambda RBAC | You're not in `admins` |
| `ValidationException` on token update | DynamoDB | `used` is a reserved word, so use `ExpressionAttributeNames` |

## Author
**Cautchy Bailly**: Cloud Engineer · [github.com/cautchybailly](https://github.com/cautchybailly)

© 2026 Cautchy Bailly. All rights reserved. See [LICENSE](LICENSE).
