from pydantic import BaseModel, Field


class PayRequest(BaseModel):
    user_id: str
    amount: float = Field(gt=0)
    merchant_id: str
    geo_lat: float
    geo_lon: float
    timestamp: int | None = None


class PayResponse(BaseModel):
    status: str
    txn_id: str
    risk_score: float
    reason: str


class HealthResponse(BaseModel):
    status: str
