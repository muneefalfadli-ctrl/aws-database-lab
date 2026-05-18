# 1. Network Topology: VPC & Subnets
resource "aws_vpc" "db_lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "db-lab-vpc" }
}

resource "aws_subnet" "public_web" {
  vpc_id                  = aws_vpc.db_lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-web-subnet" }
}

# RDS requires at least TWO subnets in different Availability Zones for high-availability constraints
resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.db_lab_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "private-db-1" }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.db_lab_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "private-db-2" }
}

# 2. RDS Subnet Group (Tells RDS which subnets it can use)
resource "aws_db_subnet_group" "rds_group" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]
  tags       = { Name = "My DB Subnet Group" }
}

# 3. Security Rules (Firewalls)
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  vpc_id      = aws_vpc.db_lab_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For your local SSH connection
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "database-sg"
  vpc_id      = aws_vpc.db_lab_vpc.id

  ingress {
    description     = "Allow PostgresSQL traffic strictly from the Web Server"
    from_port       = 5432 # CHANGED: PostgreSQL default Port
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # Cross-referencing Security Groups
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Compute: App Server
resource "aws_instance" "app_server" {
  ami                    = "ami-0c7217cdde317cfec" # Ensure this is a valid Ubuntu 22.04 AMI in your region
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_web.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  tags                   = { Name = "App-Server" }
}

# 5. Managed Database: AWS RDS MySQL Instance
resource "aws_db_instance" "database" {
  allocated_storage      = 20
  max_allocated_storage  = 50
  db_name                = "cloudenginedb"
  
  engine                 = "postgres"      
  engine_version         = "16"            
  instance_class         = "db.t3.small"   
  
  # FIXED: 'admin' is reserved in Postgres, using the engine default instead
  username               = "postgres"      
  password               = "CloudEngineerPass123!" 
  
  db_subnet_group_name   = aws_db_subnet_group.rds_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}



#6. Manage Cloudwatch 
resource "aws_cloudwatch_metric_alarm" "db_cpu_alarm" {
  alarm_name          = "rds-mysql-high-cpu-utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300" # 5 minutes
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors rds mysql cpu utilization"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.database.identifier
  }
}






