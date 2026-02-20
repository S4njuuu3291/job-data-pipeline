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

# NOTE: Access Key dikelola secara manual di AWS Console, bukan oleh Terraform
# Ini untuk menghindari "LimitExceeded" error karena AWS hanya allow 2 access keys per user
# Jika perlu access key baru, buat manually di IAM Console dan masukkan ke GitHub Secrets
# resource "aws_iam_access_key" "jobscraper_bot" {
#   user = aws_iam_user.jobscraper_bot.name
# }

resource "aws_iam_policy" "scraper_s3_write_policy" {
  name        = "jobscraper_s3_write_policy"
  description = "Write access for scraper to Bronze S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.bronze.arn]
      },
      {
        Sid      = "AllowObjectReadWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${aws_s3_bucket.bronze.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "jobscraper_bot_s3_write" {
  user       = aws_iam_user.jobscraper_bot.name
  policy_arn = aws_iam_policy.scraper_s3_write_policy.arn
}

# =========================================================
#                    BUCKET RESOURCE
# =========================================================

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

# =========================================================
#                    ECR REPOSITORY
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
#                    LAMBDA RESOURCE
# =========================================================

# Resource untuk Kalibrr
resource "aws_lambda_function" "kalibrr" {
  function_name = "jobscraper-kalibrr"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  
  publish       = false 

  # FIX: Mengatasi bug "Provider produced inconsistent final plan"
  lifecycle {
    ignore_changes = [publish]
  }

  image_config {
    command = ["src.entrypoint.handlers.kalibrr_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
    }
  }

  memory_size = 3008
  timeout     = 900
}

# Resource untuk Glints
resource "aws_lambda_function" "glints" {
  function_name = "jobscraper-glints"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  
  publish       = false 

  # FIX: Mengatasi bug "Provider produced inconsistent final plan"
  lifecycle {
    ignore_changes = [publish]
  }

  image_config {
    command = ["src.entrypoint.handlers.glints_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
    }
  }

  memory_size = 3008
  timeout     = 900
}

# Resource untuk Jobstreet
resource "aws_lambda_function" "jobstreet" {
  function_name = "jobscraper-jobstreet"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  architectures = ["x86_64"]
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  
  publish       = false 

  # FIX: Mengatasi bug "Provider produced inconsistent final plan"
  lifecycle {
    ignore_changes = [publish]
  }

  image_config {
    command = ["src.entrypoint.handlers.jobstreet_handler"]
  }

  environment {
    variables = {
      PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
      AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
    }
  }

  memory_size = 3008
  timeout     = 900
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

# =========================================================
#               EVENTBRIDGE SCHEDULER (CRON)
# =========================================================

resource "aws_lambda_permission" "allow_eventbridge_kalibrr" {
  statement_id = "AllowExecutionFromEventBridge"
  action       = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kalibrr.function_name
  principal    = "events.amazonaws.com"
}

resource "aws_lambda_permission" "allow_eventbridge_glints" {
  statement_id = "AllowExecutionFromEventBridge"
  action       = "lambda:InvokeFunction"
  function_name = aws_lambda_function.glints.function_name
  principal    = "events.amazonaws.com"
}

resource "aws_lambda_permission" "allow_eventbridge_jobstreet" {
  statement_id = "AllowExecutionFromEventBridge"
  action       = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jobstreet.function_name
  principal    = "events.amazonaws.com"
}

# Rules jam 5 pagi WIB (22 UTC) setiap hari
resource "aws_cloudwatch_event_rule" "daily_scrape" {
  name                = "daily_scrape_rule"
  schedule_expression = "cron(0 22 * * ? *)"
}

# Target
resource "aws_cloudwatch_event_target" "kalibrr_target" {
  rule     = aws_cloudwatch_event_rule.daily_scrape.name
  target_id = "TriggerKalibrrLambda"
  arn       = aws_lambda_function.kalibrr.arn
}

resource "aws_cloudwatch_event_target" "glints_target" {
  rule     = aws_cloudwatch_event_rule.daily_scrape.name
  target_id = "TriggerGlintsLambda"
  arn       = aws_lambda_function.glints.arn
}

resource "aws_cloudwatch_event_target" "jobstreet_target" {
  rule     = aws_cloudwatch_event_rule.daily_scrape.name
  target_id = "TriggerJobstreetLambda"
  arn       = aws_lambda_function.jobstreet.arn
}