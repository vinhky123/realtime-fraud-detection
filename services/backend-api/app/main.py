from uuid import uuid4

from fastapi import FastAPI

from app.config import settings
from app.models.schemas import HealthResponse, PayRequest, PayResponse
from app.services.decision import evaluate
from app.services.feature_store import get_features

app = FastAPI(title="Fraud Detection API", version="0.1.0")


@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(status="ok")


@app.post("/pay", response_model=PayResponse)
async def pay(req: PayRequest):
    features = get_features(req.user_id)
    risk_score, reason = evaluate(req.amount, req.geo_lat, req.geo_lon, features)
    status = "DECLINE" if risk_score > settings.risk_threshold else "APPROVE"
    return PayResponse(status=status, txn_id=str(uuid4()), risk_score=risk_score, reason=reason)
