# cyber-car-washer-be

Backend serverless che, dato l'UID di una card, genera in modo deterministico le 16 coppie di chiavi (Key A / Key B, 6 byte ciascuna) dei settori della card.

Il servizio è una AWS Lambda in Python esposta tramite un Application Load Balancer in HTTPS; l'infrastruttura è descritta con Terraform.

## Come funziona

1. Il client invia una `POST` all'ALB con l'header `X-Api-Key` e un body JSON contenente l'UID in esadecimale.
2. L'ALB inoltra la richiesta alla Lambda solo se `X-Api-Key` corrisponde al valore configurato; in tutti gli altri casi risponde `404 Not Found`.
3. La Lambda valida il payload, inizializza il PRNG con `uid XOR DEFAULT_ACCESS_KEYS_KEY` e genera 16 coppie di chiavi da 6 byte.

A parità di UID le chiavi restituite sono sempre le stesse.

```
client ──HTTPS──▶ ALB (:443, cert self-signed)
                   │  regola: X-Api-Key == var.api_key
                   ▼
                 Lambda (cyber_car_washer_be.handler.lambda_handler)
```

## API

### Richiesta

```http
POST / HTTP/1.1
Host: <alb_dns_name>
Content-Type: application/json
X-Api-Key: <api_key>

{"uid": "<32 caratteri esadecimali>"}
```

| Campo | Tipo   | Descrizione                                     |
|-------|--------|-------------------------------------------------|
| `uid` | string | UID della card in esadecimale, lunghezza 32 caratteri |

### Risposta `200`

```json
{
  "keys": [
    { "key_a": 123456789012345, "key_b": 98765432109876 },
    ...
  ]
}
```

`keys` contiene 16 elementi, uno per settore; `key_a` e `key_b` sono interi.

### Risposta `400`

Restituita quando il body non è un JSON valido o l'UID non rispetta il formato:

```json
{ "error": "invalid_request", "details": [ ... ] }
```

### Esempio con curl

```bash
curl -k -X POST "https://$(terraform -chdir=terraform output -raw alb_dns_name)/" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{"uid": "00112233445566778899aabbccddeeff"}'
```

`-k` è necessario perché il certificato dell'ALB è self-signed (vedi [Note](#note)).

## Struttura del progetto

```
.
├── src/cyber_car_washer_be/
│   ├── handler.py       # entrypoint della Lambda e generazione delle chiavi
│   ├── models.py        # modelli Pydantic di richiesta e risposta
│   └── responses.py     # helper per le risposte nel formato ALB
├── terraform/
│   ├── vpc.tf           # VPC, subnet pubbliche, internet gateway
│   ├── security_groups.tf
│   ├── acm.tf           # certificato self-signed importato in ACM
│   ├── alb.tf           # ALB, listener HTTPS, regola su X-Api-Key
│   ├── lambda.tf        # funzione Lambda, ruolo IAM, permesso di invocazione
│   ├── lambda_build.tf  # build del pacchetto in container Docker
│   ├── build_lambda.sh  # script di packaging (uv + zip)
│   ├── variables.tf
│   └── outputs.tf
├── pyproject.toml
└── uv.lock
```

## Sviluppo locale

Requisiti: Python 3.13+ e [uv](https://docs.astral.sh/uv/).

```bash
uv sync
```

Per invocare l'handler in locale con un evento ALB di esempio:

```bash
uv run python -m cyber_car_washer_be.handler
```

## Deploy

Requisiti:

- Terraform >= 1.5
- Docker (la build del pacchetto avviene nell'immagine `public.ecr.aws/sam/build-python<versione>`, così le wheel compilate come `pydantic-core` corrispondono al runtime Lambda)
- Credenziali AWS configurate

```bash
cd terraform
terraform init
terraform apply -var="api_key=<segreto>"
```

Terraform ricostruisce automaticamente `terraform/build/lambda.zip` quando cambiano i sorgenti, `pyproject.toml`, `uv.lock`, lo script di build, l'architettura o la versione di Python.

### Variabili

| Variabile               | Default              | Descrizione                                      |
|-------------------------|----------------------|--------------------------------------------------|
| `api_key`               | — (obbligatoria)     | Valore richiesto nell'header `X-Api-Key`         |
| `aws_region`            | `eu-west-1`          | Regione AWS                                      |
| `project_name`          | `cyber-car-washer`   | Prefisso dei nomi delle risorse                  |
| `vpc_cidr`              | `10.0.0.0/16`        | CIDR della VPC                                   |
| `public_subnet_cidrs`   | `["10.0.1.0/24", "10.0.2.0/24"]` | Subnet pubbliche, una per AZ         |
| `lambda_architecture`   | `arm64`              | `arm64` oppure `x86_64`                          |
| `lambda_python_version` | `3.13`               | Versione del runtime Python della Lambda         |
| `lambda_memory_size`    | `128`                | Memoria della Lambda (MB)                        |
| `lambda_timeout`        | `10`                 | Timeout della Lambda (secondi)                   |

I file `*.tfvars` sono esclusi da git: è possibile salvare lì `api_key` invece di passarla da riga di comando.

### Output

| Output                 | Descrizione                         |
|------------------------|-------------------------------------|
| `alb_dns_name`         | DNS pubblico dell'ALB               |
| `lambda_function_name` | Nome della funzione Lambda          |

## Note

- **Certificato TLS**: l'ALB è raggiungibile solo tramite il DNS generato da AWS, quindi ACM non può emettere un certificato pubblico. Terraform genera un certificato self-signed (validità 1 anno) e lo importa in ACM; i client devono disabilitare la verifica TLS.
- **Health check** del target group disabilitati: una richiesta sintetica fallirebbe la validazione (400) e marcherebbe la Lambda come unhealthy.
- **Autenticazione**: l'unica protezione è la shared secret in `X-Api-Key`, verificata a livello di ALB.
