import logging

import boto3

from app.config import settings

logger = logging.getLogger(__name__)

_dynamodb = boto3.resource("dynamodb", region_name=settings.aws_region)
_table = _dynamodb.Table(settings.dynamodb_table)


def get_features(user_id: str) -> dict | None:
    """Uber pattern: read pre-computed features for a user. None = cold start."""
    try:
        resp = _table.get_item(Key={"user_id": user_id})
        return resp.get("Item")
    except Exception:
        logger.exception("DynamoDB GetItem failed for user_id=%s", user_id)
        return None
