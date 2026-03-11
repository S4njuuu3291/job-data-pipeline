# =========================================================
#                DATA SOURCES
# =========================================================

data "aws_caller_identity" "current" {}

# =========================================================
#              GITHUB OIDC PROVIDER FOR CI/CD
# =========================================================

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform"
    Purpose   = "GitHubOIDC"
  }
}

resource "aws_iam_role" "github_actions_role" {
  name = "jobscraper-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:S4njuuu3291/job-data-pipeline:*"
        }
      }
    }]
  })

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform"
    Purpose   = "GitHubActionsRole"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# =========================================================
#              TERRAFORM STATE LOCKING (DYNAMODB)
# =========================================================

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "jobscraper-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform"
    Purpose   = "StateLocking"
  }
}

# =========================================================
#                   SQS DEAD LETTER QUEUE
# =========================================================

resource "aws_sqs_queue" "scraper_dlq" {
  name                      = "jobscraper-dlq"
  message_retention_seconds = 1209600 # 14 hari
  tags = {
    Project = "Job-Scraper"
    Purpose = "DeadLetterQueue"
  }
}

# CloudWatch Alarm: Berbunyi jika ada pesan masuk ke DLQ (indikasi ada scraper gagal)
resource "aws_cloudwatch_metric_alarm" "dlq_alarm" {
  alarm_name          = "jobscraper-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300 # Cek tiap 5 menit
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Ada Lambda scraper yang gagal dan masuk ke Dead Letter Queue"
  dimensions = {
    QueueName = aws_sqs_queue.scraper_dlq.name
  }
}

# =========================================================
#                   IAM USER RESOURCE
# =========================================================

resource "aws_iam_user" "jobscraper_bot" {
  name = "jobscraper_bot-crawler-bot"

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform-Executor"
  }
}

resource "aws_iam_policy" "scraper_s3_write_policy" {
  name        = "jobscraper_s3_write_policy"
  description = "Write access for scraper to Bronze and Silver S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = [aws_s3_bucket.bronze.arn, aws_s3_bucket.silver.arn]
      },
      {
        Sid      = "AllowBronzeObjectReadWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.bronze.arn}/*"]
      },
      {
        Sid      = "AllowSilverObjectWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${aws_s3_bucket.silver.arn}/*"]
      }
    ]
  })
}

# Policy untuk mengizinkan Lambda mengirim pesan ke SQS DLQ
resource "aws_iam_policy" "lambda_dlq_policy" {
  name = "jobscraper_lambda_dlq_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.scraper_dlq.arn
    }]
  })
}

resource "aws_iam_policy" "lambda_glue_policy" {
  name        = "jobscraper_lambda_glue_policy"
  description = "Allow Lambda to create partitions in Glue Catalog (silver layer)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:BatchCreatePartition",
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:DeletePartition"
        ]
        Resource = "*"
      }
    ]
  })
}

# =========================================================
#           IAM ROLE UNTUK SLACK ALERT LAMBDA
# =========================================================

resource "aws_iam_role" "slack_lambda_role" {
  name = "jobscraper_slack_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "Job-Scraper"
    Purpose   = "SlackAlertLambda"
    ManagedBy = "Terraform"
  }
}

# Policy untuk Athena (query job postings dari Silver layer)
resource "aws_iam_policy" "slack_athena_policy" {
  name        = "jobscraper_slack_athena_policy"
  description = "Allow Slack Lambda to query Athena for new job postings"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAthenaQueryExecution"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowGlueAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLakeFormationAccess"
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:GetDataLakePrincipal"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy untuk SSM (get Slack webhook URL dari Parameter Store)
resource "aws_iam_policy" "slack_ssm_policy" {
  name        = "jobscraper_slack_ssm_policy"
  description = "Allow Slack Lambda to retrieve webhook URL from SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetParameter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/jobscraper/slack/*"
      }
    ]
  })
}

# Policy untuk S3 (read Athena query results)
resource "aws_iam_policy" "slack_s3_policy" {
  name        = "jobscraper_slack_s3_policy"
  description = "Allow Slack Lambda to read S3 query results from Athena"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAthenaQueryResultsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation",
          "s3:DeleteObject"
        ]
        Resource = [
          data.aws_s3_bucket.athena_query_results.arn,
          "${data.aws_s3_bucket.athena_query_results.arn}/*"
        ]
      }
    ]
  })
}

# Lake Formation Data Lake Settings - Add Lambda role as Data Lake Admin
# Also disable cross-account filtering to simplify permissions
resource "aws_lakeformation_data_lake_settings" "slack_lambda_admin" {
  depends_on = [aws_iam_role.slack_lambda_role]

  admins = [
    aws_iam_role.slack_lambda_role.arn
  ]

  # Disable fine-grained access control which is causing column-level permission issues
  allow_external_data_filtering = false
}

# Athena Workgroup untuk Slack Lambda
resource "aws_athena_workgroup" "slack_alert_workgroup" {
  name            = "jobscraper-slack-alert-workgroup"
  force_destroy   = true
  state           = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${data.aws_s3_bucket.athena_query_results.id}/athena-query-results/jobscraper/"
    }

    engine_version {
      selected_engine_version = "AUTO"
    }
  }

  tags = {
    Project = "Job-Scraper"
    Purpose = "SlackAlerts"
  }
}

# Attach policies ke slack_lambda_role
resource "aws_iam_role_policy_attachment" "slack_athena_attachment" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = aws_iam_policy.slack_athena_policy.arn
}

resource "aws_iam_role_policy_attachment" "slack_ssm_attachment" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = aws_iam_policy.slack_ssm_policy.arn
}

resource "aws_iam_role_policy_attachment" "slack_s3_attachment" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = aws_iam_policy.slack_s3_policy.arn
}

# Also attach basic Lambda execution policy untuk logs ke CloudWatch
resource "aws_iam_role_policy_attachment" "slack_basic_execution" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =========================================================
#        LAMBDA LAYER - SLACK ALERT DEPENDENCIES
# =========================================================

# Zip file untuk Lambda Layer (requests library)
data "archive_file" "slack_alert_layer" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-layers/slack-alert-layer"
  output_path = "${path.module}/../.terraform-artifacts/slack-alert-layer.zip"
}

resource "aws_lambda_layer_version" "slack_alert_layer" {
  filename            = data.archive_file.slack_alert_layer.output_path
  layer_name          = "jobscraper-slack-alert-layer"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = data.archive_file.slack_alert_layer.output_base64sha256

  depends_on = [aws_iam_role.slack_lambda_role]
}

resource "aws_iam_user_policy_attachment" "jobscraper_bot_s3_write" {
  user       = aws_iam_user.jobscraper_bot.name
  policy_arn = aws_iam_policy.scraper_s3_write_policy.arn
}

# =========================================================
#                     BUCKET RESOURCE
# =========================================================

# BRONZE

resource "aws_s3_bucket" "bronze" {
  bucket        = "jobscraper-bronze-data-8424560"
  force_destroy = true

  tags = {
    Layer   = "Bronze"
    Project = "Job-Scraper"
    Owner   = "Sanju"
  }
}

resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SILVER

resource "aws_s3_bucket" "silver" {
  bucket        = "jobscraper-silver-data-8424560"
  force_destroy = true

  tags = {
    Layer   = "Silver"
    Project = "Job-Scraper"
    Owner   = "Sanju"
  }
}

resource "aws_s3_bucket_public_access_block" "silver" {
  bucket = aws_s3_bucket.silver.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# QUERY RESULTS (untuk Athena) - menggunakan bucket yang sudah ada
# Bucket: weather-data-lake-sanju (sudah ada di AWS account)
# Path: athena-query-results/Unsaved/

data "aws_s3_bucket" "athena_query_results" {
  bucket = "weather-data-lake-sanju"
}

# =========================================================
#                     ECR REPOSITORY
# =========================================================

resource "aws_ecr_repository" "scraper_repo" {
  name                 = "job-scraper-lambda"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_ecr_image" "scraper_latest" {
  repository_name = aws_ecr_repository.scraper_repo.name
  image_tag       = "latest"
}

resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.scraper_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Hanya simpan 1 image terbaru, hapus sisanya"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 1
      }
      action = { type = "expire" }
    }]
  })
}

# =========================================================
#                     LAMBDA RESOURCE
# =========================================================

# Resource untuk Kalibrr
resource "aws_lambda_function" "kalibrr" {
  function_name = "jobscraper-kalibrr"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"

  publish = false

  lifecycle {
    ignore_changes = [publish]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.scraper_dlq.arn
  }

  image_config {
    command = ["src.entrypoint.handlers.kalibrr_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
      SCRAPE_KEYWORDS          = "data-engineer-intern,etl-developer-intern,big-data-intern,bi-engineer-intern"
    }
  }

  memory_size = 2048
  timeout     = 900
}

# Resource untuk Glints
resource "aws_lambda_function" "glints" {
  function_name = "jobscraper-glints"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"

  publish = false

  lifecycle {
    ignore_changes = [publish]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.scraper_dlq.arn
  }

  image_config {
    command = ["src.entrypoint.handlers.glints_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
      SCRAPE_KEYWORDS          = "data+engineer+intern,etl+developer+intern,big+data+intern,bi+engineer+intern"
    }
  }

  memory_size = 2048
  timeout     = 900
}

# Resource untuk Jobstreet
resource "aws_lambda_function" "jobstreet" {
  function_name = "jobscraper-jobstreet"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"

  publish = false

  lifecycle {
    ignore_changes = [publish]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.scraper_dlq.arn
  }

  image_config {
    command = ["src.entrypoint.handlers.jobstreet_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
      SCRAPE_KEYWORDS          = "data-engineer-intern,etl-developer-intern,big-data-intern,bi-engineer-intern"
    }
  }

  memory_size = 2048
  timeout     = 900
}

# Resource untuk Silver Layer Transformation
resource "aws_lambda_function" "silver_layer" {
  function_name = "jobscraper-silver-layer"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"

  publish = false

  lifecycle {
    ignore_changes = [publish]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.scraper_dlq.arn
  }

  image_config {
    command = ["src.entrypoint.handlers.silver_layer_handler"]
  }

  environment {
    variables = {
      platform                   = "kalibrr,glints,jobstreet"
      AWS_S3_BUCKET_NAME         = aws_s3_bucket.bronze.id
      AWS_S3_SILVER_BUCKET_NAME  = aws_s3_bucket.silver.id
      AWS_GLUE_DATABASE_NAME     = "jobscraper_db"
      AWS_GLUE_SILVER_TABLE_NAME = "jobscraper_silver_table"
    }
  }

  memory_size = 1024
  timeout     = 300
}

# Resource untuk Slack Alert
data "archive_file" "slack_alert_code" {
  type        = "zip"
  source_dir  = "${path.module}/../src/slack-alert"
  output_path = "${path.module}/../.terraform-artifacts/slack-alert.zip"
}

resource "aws_lambda_function" "slack_alert" {
  function_name = "jobscraper-slack-alert"
  role          = aws_iam_role.slack_lambda_role.arn
  filename      = data.archive_file.slack_alert_code.output_path
  source_code_hash = data.archive_file.slack_alert_code.output_base64sha256
  handler       = "slack_handler.lambda_handler"
  runtime       = "python3.12"
  architectures = ["x86_64"]

  layers = [
    aws_lambda_layer_version.slack_alert_layer.arn
  ]

  environment {
    variables = {
      AWS_GLUE_DATABASE_NAME = "jobscraper_db"
    }
  }

  memory_size = 512
  timeout     = 60

  depends_on = [
    aws_iam_role_policy_attachment.slack_athena_attachment,
    aws_iam_role_policy_attachment.slack_ssm_attachment,
    aws_iam_role_policy_attachment.slack_s3_attachment,
    aws_iam_role_policy_attachment.slack_basic_execution,
    aws_lambda_layer_version.slack_alert_layer
  ]

  tags = {
    Project   = "Job-Scraper"
    Purpose   = "SlackAlerts"
    ManagedBy = "Terraform"
  }
}

# =========================================================
#                    IAM ROLE LAMBDA
# =========================================================

resource "aws_iam_role" "lambda_exec_role" {
  name = "jobscraper_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.scraper_s3_write_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_ecr" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Attach DLQ policy ke role Lambda
resource "aws_iam_role_policy_attachment" "lambda_dlq" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dlq_policy.arn
}

# Attach Glue policy ke role Lambda (untuk silver layer transformation)
resource "aws_iam_role_policy_attachment" "lambda_glue" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_glue_policy.arn
}

# =========================================================
#           EVENTBRIDGE SCHEDULER (CRON) → STATE MACHINE
# =========================================================

# Event Rule untuk jam 9 pagi WIB (02:00 UTC)
# Strategi: Capture postingan tadi malam + pagi, apply saat HR aktif
resource "aws_cloudwatch_event_rule" "scrape_morning" {
  name                = "jobscraper-schedule-morning"
  schedule_expression = "cron(0 2 * * ? *)"
  description         = "Trigger State Machine jam 09:00 WIB - Prime time HR activity (pagi)"
}

resource "aws_cloudwatch_event_target" "scrape_morning_target" {
  rule      = aws_cloudwatch_event_rule.scrape_morning.name
  target_id = "TriggerStateMachineMorning"
  arn       = aws_sfn_state_machine.joscraper_orchestrator.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# Event Rule untuk jam 4 sore WIB (09:00 UTC)
# Strategi: Capture postingan setelah makan siang, apply sebelum HR tutup laptop
resource "aws_cloudwatch_event_rule" "scrape_evening" {
  name                = "jobscraper-schedule-evening"
  schedule_expression = "cron(0 9 * * ? *)"
  description         = "Trigger State Machine jam 16:00 WIB - Sebelum HR tutup (sore)"
}

resource "aws_cloudwatch_event_target" "scrape_evening_target" {
  rule      = aws_cloudwatch_event_rule.scrape_evening.name
  target_id = "TriggerStateMachineEvening"
  arn       = aws_sfn_state_machine.joscraper_orchestrator.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# IAM Role untuk EventBridge
resource "aws_iam_role" "eventbridge_role" {
  name = "jobscraper_eventbridge_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "eventbridge_state_machine_policy" {
  name        = "jobscraper_eventbridge_state_machine_policy"
  description = "Policy untuk EventBridge invoke State Machine"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "states:StartExecution"
      ]
      Resource = aws_sfn_state_machine.joscraper_orchestrator.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_state_machine_attach" {
  role       = aws_iam_role.eventbridge_role.id
  policy_arn = aws_iam_policy.eventbridge_state_machine_policy.arn
}

# =========================================================
#                    GLUE DATA CATALOG
# =========================================================

resource "aws_glue_catalog_database" "jobscraper_db" {
  name        = "jobscraper_db"
  description = "Glue Catalog Database untuk Job Scraper Pipeline"
}

resource "aws_iam_role" "glue_role" {
  name = "jobscraper_glue_crawler_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_s3_read" {
  name        = "jobscraper_glue_s3_read_policy"
  description = "Read access untuk Glue Crawler ke S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
      ]
      Resource = [
        aws_s3_bucket.bronze.arn,
        "${aws_s3_bucket.bronze.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_read_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_read.arn
}

# SILVER TABLE
resource "aws_glue_catalog_table" "silver_table" {
  name          = "jobscraper_silver_table"
  database_name = aws_glue_catalog_database.jobscraper_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
    "typeOfData"     = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.silver.id}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "job_id"
      type = "string"
    }
    columns {
      name = "job_title"
      type = "string"
    }
    columns {
      name = "company_name"
      type = "string"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "job_url"
      type = "string"
    }

    columns {
      name = "platform"
      type = "string"
    }

    columns {
      name = "scraped_at"
      type = "string"
    }
    columns {
      name = "keyword"
      type = "string"
    }
  }

  partition_keys {
    name = "ingestion_date"
    type = "string"
  }
}

# =========================================================
#               STATE MACHINE (STEP FUNCTIONS)
# =========================================================

resource "aws_iam_role" "step_functions_role" {
  name = "jobscraper_step_functions_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "step_functions_policy" {
  name        = "jobscraper_step_functions_policy"
  description = "Policy untuk Step Functions invoke Lambda dan logging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaInvoke"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "${aws_lambda_function.kalibrr.arn}:*",
          "${aws_lambda_function.glints.arn}:*",
          "${aws_lambda_function.jobstreet.arn}:*",
          "${aws_lambda_function.silver_layer.arn}:*",
          "${aws_lambda_function.slack_alert.arn}:*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_functions_policy" {
  role       = aws_iam_role.step_functions_role.id
  policy_arn = aws_iam_policy.step_functions_policy.arn
}

# =========================================================
#           CLOUDWATCH LOG GROUP STEP FUNCTIONS
# =========================================================

resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/stepfunctions/jobscraper-orchestrator"
  retention_in_days = 7

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform"
    Purpose   = "StepFunctionsLogging"
  }
}

resource "aws_sfn_state_machine" "joscraper_orchestrator" {
  name     = "jobscraper_orchestrator"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/step_functions/JobScraperMachine.asl.json", {
    kalibrr_lambda_arn      = aws_lambda_function.kalibrr.arn
    glints_lambda_arn       = aws_lambda_function.glints.arn
    jobstreet_lambda_arn    = aws_lambda_function.jobstreet.arn
    silver_layer_lambda_arn = aws_lambda_function.silver_layer.arn
    slack_alert_lambda_arn  = aws_lambda_function.slack_alert.arn
  })

  logging_configuration {
    level                  = "ERROR"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
  }
}

# SSM PARAMETER STORE

resource "aws_ssm_parameter" "slack_webhook_url" {
  name  = "/jobscraper/slack/webhook_url"
  type  = "SecureString"
  value = var.slack_webhook_url != "" ? var.slack_webhook_url : "default"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Project   = "Job-Scraper"
    ManagedBy = "Terraform"
    Purpose   = "SlackWebhookURL"
  }
}