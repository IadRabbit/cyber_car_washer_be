locals {
  build_dir = "${path.module}/build"
  zip_path  = "${local.build_dir}/lambda.zip"
  docker_platform = var.lambda_architecture == "arm64" ? "linux/arm64" : "linux/amd64"
}

# Runs build_lambda.sh inside AWS's official SAM build image so the
# installed wheels (pydantic-core is a compiled extension) match Lambda's
# actual runtime/glibc for the target architecture, instead of whatever
# the dev machine happens to be. The container has the repo mounted in and
# writes the finished zip straight to build/lambda.zip.
resource "null_resource" "lambda_build" {
  triggers = {
    pyproject_hash = filesha256("${path.module}/../pyproject.toml")
    lockfile_hash  = filesha256("${path.module}/../uv.lock")
    handler_hash   = filesha256("${path.module}/../src/cyber_car_washer_be/handler.py")
    models_hash    = filesha256("${path.module}/../src/cyber_car_washer_be/models.py")
    responses_hash = filesha256("${path.module}/../src/cyber_car_washer_be/responses.py")
    build_script   = filesha256("${path.module}/build_lambda.sh")
    arch           = var.lambda_architecture
    python_version = var.lambda_python_version
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      set -euo pipefail
      docker run --rm \
        --platform ${local.docker_platform} \
        -e ARCH=${var.lambda_architecture} \
        -e PYTHON_VERSION=${var.lambda_python_version} \
        -v "$(cd .. && pwd)":/workspace \
        -w /workspace \
        public.ecr.aws/sam/build-python${var.lambda_python_version}:latest \
        bash -c "pip install --quiet uv && bash terraform/build_lambda.sh"
    EOT
  }
}

# depends_on on a data source defers reading it until after the dependency
# has applied (unlike depends_on on a plain function call, which doesn't
# stop Terraform from evaluating it at plan time before the zip exists).
data "local_file" "lambda_zip" {
  filename = local.zip_path

  depends_on = [null_resource.lambda_build]
}
