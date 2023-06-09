resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  associate_public_ip_address = true
  instance_type               = var.bastion_instance_type
  key_name                    = aws_key_pair.bastion_ssh_key.key_name
  user_data                   = file("${path.module}/install_ansible.sh")
  subnet_id                   = var.subnets_web_tier[0]
  vpc_security_group_ids      = [var.sg_bastion]
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ssm-user"
    private_key = file("${path.root}/.ssh/bastion")
  }

  provisioner "file" {
    source      = "${path.root}/.ssh"
    destination = "/home/ssm-user"
  }

  provisioner "remote-exec" {
    inline = [
      "git clone --depth 1 --branch master --no-checkout https://github.com/laslopaul/terraform-aws-three-tier-arch.git",
      "cd terraform-aws*",
      "git sparse-checkout set ansible",
      "git checkout master",
      "chmod 600 ~/.ssh/bastion"
    ]
  }

  tags = {
    Name = "bastion"
  }
}

# Add IAM policy allowing to describe EC2 instances, which is required by Ansible dynamic inventory
resource "aws_iam_policy" "describe_ec2" {
  name        = "describe_ec2_policy"
  path        = "/"
  description = "Describe EC2 instances"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Create an IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# Attach EC2 IAM role to describe_ec2 policy
resource "aws_iam_policy_attachment" "ec2_describe_attachment" {
  name       = "ec2_describe_attachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = aws_iam_policy.describe_ec2.arn
}

# Create IAM instance profile for Bastion
resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion_profile"
  role = aws_iam_role.ec2_role.name
}
