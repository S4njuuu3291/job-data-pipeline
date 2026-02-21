# =========================================================
#                   IAM USER & S3 STORAGE
# =========================================================

resource "aws_iam_user" "jobscraper_bot" {
  name = "jobscraper_bot-crawler-bot"
  tags = { Project = "Job-Scraper", ManagedBy = "Terraform" }
}

resource "aws_iam_policy" "scraper_s3_write_policy" {
  name        = "jobscraper_s3_write_policy"
  description = "Write access for scraper to Bronze S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AllowListBucket", Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.bronze.arn] },
      { Sid = "AllowObjectReadWrite", Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${aws_s3_bucket.bronze.arn}/*"] }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "jobscraper_bot_s3_write" {
  user       = aws_iam_user.jobscraper_bot.name
  policy_arn = aws_iam_policy.scraper_s3_write_policy.arn
}

resource "aws_s3_bucket" "bronze" {
  bucket        = "jobscraper-bronze-data-8424560"
  force_destroy = true
}

# =========================================================
#                   ECR & LAMBDA RESOURCES
# =========================================================

resource "aws_ecr_repository" "scraper_repo" {
  name                 = "job-scraper-lambda"
  force_delete         = true
  image_tag_mutability = "MUTABLE"
}

data "aws_ecr_image" "scraper_latest" {
  repository_name = aws_ecr_repository.scraper_repo.name
  image_tag       = "latest"
}

# IAM Role untuk Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "jobscraper_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
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

# Template Lambda (DRY principle)
locals {
  lambda_env = {
    PLAYWRIGHT_BROWSERS_PATH = "/opt/pw-browsers"
    AWS_S3_BUCKET_NAME       = aws_s3_bucket.bronze.id
    TZ                       = "Asia/Jakarta" # FIX: Timezone Jakarta
  }
}

resource "aws_lambda_function" "kalibrr" {
  function_name = "jobscraper-kalibrr"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  image_config { command = ["src.entrypoint.handlers.kalibrr_handler"] }
  environment { variables = local.lambda_env }
  memory_size = 3008
  timeout     = 900
}

resource "aws_lambda_function" "glints" {
  function_name = "jobscraper-glints"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  image_config { command = ["src.entrypoint.handlers.glints_handler"] }
  environment { variables = local.lambda_env }
  memory_size = 3008
  timeout     = 900
}

resource "aws_lambda_function" "jobstreet" {
  function_name = "jobscraper-jobstreet"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.scraper_repo.repository_url}@${data.aws_ecr_image.scraper_latest.image_digest}"
  image_config { command = ["src.entrypoint.handlers.jobstreet_handler"] }
  environment { variables = local.lambda_env }
  memory_size = 3008
  timeout     = 900
}

# =========================================================
#                EVENTBRIDGE & GLUE CATALOG
# =========================================================

resource "aws_cloudwatch_event_rule" "daily_scrape" {
  name                = "daily_scrape_rule"
  schedule_expression = "cron(0 22 * * ? *)" # 05:00 WIB
}

# Glue Database
resource "aws_glue_catalog_database" "jobscraper_db" {
  name = "jobscraper_db"
}

# Glue Role
resource "aws_iam_role" "glue_role" {
  name = "jobscraper_glue_crawler_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_s3_read" {
  name = "jobscraper_glue_s3_read_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:ListBucket", "s3:GetObject"]
      Effect   = "Allow"
      Resource = [aws_s3_bucket.bronze.arn, "${aws_s3_bucket.bronze.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_read.arn
}

resource "aws_glue_crawler" "bronze_crawler" {
  name          = "jobscraper_bronze_crawler"
  database_name = aws_glue_catalog_database.jobscraper_db.name
  role          = aws_iam_role.glue_role.arn
  s3_target { path = "s3://${aws_s3_bucket.bronze.id}/" }
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = { Partitions = { AddOrUpdateBehavior = "InheritFromTable" } }
  })
  schedule = "cron(0 23 * * ? *)" # 06:00 WIB
}