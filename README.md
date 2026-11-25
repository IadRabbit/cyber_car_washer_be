# cyber-car-washer-be

Serverless backend that, given a card UID, deterministically generates the 16 key pairs (Key A / Key B, 6 bytes each) for the card's sectors.

> **CTF project — RomHack Camp 2026**
>
> This repository is part of **Cyber Car Washer**, a CTF challenge brought to **RomHack Camp 2026**. The challenge simulates the loyalty card system of a "cyber" car wash and is entirely based on **MIFARE Classic 1K**: the balance, the customer's personal data and the creation date live on the card, protected by per-sector keys derived on the backend.
>
> The project is made of three repositories:
>
> | Repository | Role |
> |---|---|
> | [`cyber_car_washer_be`](https://github.com/IadRabbit/cyber_car_washer_be) | Serverless backend (AWS) that derives the sector keys from the card's block 0 |
> | [`CyberCarWasherAdmin`](https://github.com/IadRabbit/CyberCarWasherAdmin) | Operator Android app: card issuing, top-up, POS, formatting |
> | [`CyberCarWasher`](https://github.com/IadRabbit/CyberCarWasher) | Customer Android app: card details and service catalog |

## Infrastructure

The component marked with ★ is the one contained in this repository.

```
┌─ AWS — VPC, 2 public subnets (Terraform) ───────────────────────────────────────┐
│  ┌──────────────────────────────────┐     ┌──────────────────────────────────┐  │
│  │ Application Load Balancer        │     │ ★ AWS Lambda (Python 3.13)       │  │
│  │ HTTPS :443, cert self-signed     │ ──▶ │ cyber_car_washer_be              │  │
│  │ valid X-Api-Key → forward        │     │ UID → 16 × (Key A, Key B)        │  │
│  │ otherwise → 404                  │     │ deterministic PRNG               │  │
│  └──────────────────────────────────┘     └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
                     ▲
                     │  POST {"uid": <block 0 hex>}  →  {"keys": [...]}
                     │  header X-Api-Key + certificate pinning
                ┌────┴──────────────────────────────────┐
┌───────────────┴──────────────┐        ┌───────────────┴──────────────┐
│ CyberCarWasherAdmin          │        │ CyberCarWasher               │
│ operator Android app         │        │ customer Android app         │
│ issuing, top-up, POS,        │        │ card data, balance,          │
│ formatting, raw edit         │        │ service catalog              │
└───────────────┬──────────────┘        └───────────────┬──────────────┘
                │ NFC                                   │ NFC
                └───────────────────┬───────────────────┘
                                    ▼
                 ┌────────────────────────────────────┐
                 │ MIFARE Classic 1K                  │
                 │                                    │
                 │ sector 0     block 0 (UID)         │
                 │ sectors 1-11 static data           │
                 │ sector 12    balance (value block) │
                 │ sector 13    creation date         │
                 │ sector 14    surname               │
                 │ sector 15    name                  │
                 │ per-sector A/B keys                │
                 └────────────────────────────────────┘
```

The service is a Python AWS Lambda exposed through an HTTPS Application Load Balancer; the infrastructure is described with Terraform.

## How it works

1. The client sends a `POST` to the ALB with the `X-Api-Key` header and a JSON body containing the UID in hex.
2. The ALB forwards the request to the Lambda only if `X-Api-Key` matches the configured value; in every other case it responds `404 Not Found`.
3. The Lambda validates the payload, seeds the PRNG with `uid XOR DEFAULT_ACCESS_KEYS_KEY` and generates 16 pairs of 6-byte keys.

The same UID always returns the same keys.

## API

### Request

```http
POST / HTTP/1.1
Host: <alb_dns_name>
Content-Type: application/json
X-Api-Key: <api_key>

{"uid": "<32 hex characters>"}
```

| Field | Type   | Description                                 |
|-------|--------|---------------------------------------------|
| `uid` | string | Card UID in hex, 32 characters long         |

### `200` response

```json
{
  "keys": [
    { "key_a": 123456789012345, "key_b": 98765432109876 },
    ...
  ]
}
```

`keys` contains 16 items, one per sector; `key_a` and `key_b` are integers.

### `400` response

Returned when the body is not valid JSON or the UID does not match the expected format:

```json
{ "error": "invalid_request", "details": [ ... ] }
```

### curl example

```bash
curl -k -X POST "https://$(terraform -chdir=terraform output -raw alb_dns_name)/" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{"uid": "00112233445566778899aabbccddeeff"}'
```

`-k` is required because the ALB certificate is self-signed (see [Notes](#notes)).

## Project structure

```
.
├── src/cyber_car_washer_be/
│   ├── handler.py       # Lambda entrypoint and key generation
│   ├── models.py        # Pydantic request/response models
│   └── responses.py     # helpers for ALB-formatted responses
├── terraform/
│   ├── vpc.tf           # VPC, public subnets, internet gateway
│   ├── security_groups.tf
│   ├── acm.tf           # self-signed certificate imported into ACM
│   ├── alb.tf           # ALB, HTTPS listener, X-Api-Key rule
│   ├── lambda.tf        # Lambda function, IAM role, invoke permission
│   ├── lambda_build.tf  # package build in a Docker container
│   ├── build_lambda.sh  # packaging script (uv + zip)
│   ├── variables.tf
│   └── outputs.tf
├── pyproject.toml
└── uv.lock
```

## Local development

Requirements: Python 3.13+ and [uv](https://docs.astral.sh/uv/).

```bash
uv sync
```

To invoke the handler locally with a sample ALB event:

```bash
uv run python -m cyber_car_washer_be.handler
```

## Deploy

Requirements:

- Terraform >= 1.5
- Docker (the package is built in the `public.ecr.aws/sam/build-python<version>` image, so compiled wheels such as `pydantic-core` match the Lambda runtime)
- Configured AWS credentials

```bash
cd terraform
terraform init
terraform apply -var="api_key=<secret>"
```

Terraform automatically rebuilds `terraform/build/lambda.zip` when the sources, `pyproject.toml`, `uv.lock`, the build script, the architecture or the Python version change.

### Variables

| Variable                | Default              | Description                                      |
|-------------------------|----------------------|--------------------------------------------------|
| `api_key`               | — (required)         | Value required in the `X-Api-Key` header         |
| `aws_region`            | `eu-west-1`          | AWS region                                       |
| `project_name`          | `cyber-car-washer`   | Resource name prefix                             |
| `vpc_cidr`              | `10.0.0.0/16`        | VPC CIDR                                         |
| `public_subnet_cidrs`   | `["10.0.1.0/24", "10.0.2.0/24"]` | Public subnets, one per AZ           |
| `lambda_architecture`   | `arm64`              | `arm64` or `x86_64`                              |
| `lambda_python_version` | `3.13`               | Lambda Python runtime version                    |
| `lambda_memory_size`    | `128`                | Lambda memory (MB)                               |
| `lambda_timeout`        | `10`                 | Lambda timeout (seconds)                         |

`*.tfvars` files are excluded from git: you can store `api_key` there instead of passing it on the command line.

### Outputs

| Output                 | Description                         |
|------------------------|-------------------------------------|
| `alb_dns_name`         | Public DNS name of the ALB          |
| `lambda_function_name` | Lambda function name                |

## Notes

- **TLS certificate**: the ALB is only reachable through the AWS-generated DNS name, so ACM cannot issue a public certificate. Terraform generates a self-signed certificate (valid for 1 year) and imports it into ACM; clients must disable TLS verification (the Android apps pin the exact certificate instead).
- Target group **health checks** are disabled: a synthetic request would fail validation (400) and mark the Lambda as unhealthy.
- **Authentication**: the only protection is the shared secret in `X-Api-Key`, checked at the ALB level.

## Development note

Across the project, only the **visual part** of the Android apps (layouts, animations, screen styling) was *vibe-coded* with the help of AI tools. This repository contains no visual part.

The following parts were **not**:

- the **design** of the challenge and of the data layout on the card;
- the **core logic** (MIFARE sector handling, authentication, value blocks, increment/decrement operations, key derivation);
- **validation** of user input and of data read from the card;
- the **integrity checks** (value block format and access bits verification before every balance operation);
- the **infrastructure** (AWS, Terraform, ALB, Lambda, certificate pinning).
