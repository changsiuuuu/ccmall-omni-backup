from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from datetime import date
from ..core.database import get_db 
from ..models import schemas as models

router = APIRouter()
templates = Jinja2Templates(directory="static")

# [Pydantic] 새 스키마에 맞춘 소문자 데이터 검증 모델
class CustomerCreate(BaseModel):
    id: str
    password: str    
    name: str
    birth_date: date
    address: str
    email: str
    phone_number: str

# --- [기능 1] 고객 리스트 조회 및 검색 ---
@router.get("/", response_class=HTMLResponse)
async def get_customers_list_page(
    request: Request, 
    search_type: str = None, 
    search_value: str = None, 
    db: Session = Depends(get_db)
):  
    query = db.query(models.Customer)

    # 검색 필터 적용 (새 컬럼명 매핑)
    if search_type and search_value:
        search_filter = f"%{search_value}%"
        if search_type == "id":
            query = query.filter(models.Customer.id.like(search_filter))
        elif search_type == "name":
            query = query.filter(models.Customer.name.like(search_filter))
        elif search_type == "addr":
            query = query.filter(models.Customer.address.like(search_filter))

    customers = query.all()
    
    return templates.TemplateResponse("customers.html", {
        "request": request, 
        "customers": customers,
        "search_type": search_type, 
        "search_value": search_value
    })

# --- [기능 2] 고객 상세 정보 제공 API (JSON 반환) ---
@router.get("/{member_id}")
async def get_customer_detail_api(
    member_id: str, 
    db: Session = Depends(get_db)
):
    customer = db.query(models.Customer).filter(models.Customer.id == member_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    
    # 프런트엔드 상세 모달로 보낼 때도 DB 컬럼명(소문자) 그대로 전송
    return {
        "id": customer.id,
        "name": customer.name,
        "email": customer.email,
        "address": customer.address,
        "phone_number": customer.phone_number,
        "birth_date": str(customer.birth_date)
    }

# --- [기능 3] 신규 고객 추가 API ---
@router.post("/")
async def create_customer(customer: CustomerCreate, db: Session = Depends(get_db)):
    # 1. 아이디 중복 체크
    existing_user = db.query(models.Customer).filter(models.Customer.id == customer.id).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="이미 존재하는 아이디입니다.")

    try:
        # 2. 필드명이 완벽히 동일하므로 dict 언패킹으로 한 번에 삽입!
        new_customer = models.Customer(**customer.dict())
        db.add(new_customer)
        db.commit()
        db.refresh(new_customer)
        return {"message": "고객이 성공적으로 추가되었습니다.", "id": new_customer.id}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"DB 저장 실패: {str(e)}")