import os


class Settings:
    dynamodb_table = os.getenv("DYNAMODB_TABLE_USER_FEATURES", "user_features_v1")
    aws_region = os.getenv("AWS_REGION", "ap-southeast-1")

    kafka_servers = os.getenv("KAFKA_BOOTSTRAP_SERVERS")
    kafka_topic = os.getenv("KAFKA_TOPIC_RAW", "raw_transactions")

    velocity_threshold = 100
    risk_threshold = 0.7
    impossible_speed_kmh = 900.0


settings = Settings()
