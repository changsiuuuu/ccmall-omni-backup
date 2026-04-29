from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from typing import List, Optional
from pydantic import BaseModel
from datetime import date
from ..core.database import get_db 
from ..models import schemas as models

router = APIRouter()
templates = Jinja2Templates(directory="static")

# 고객 정보 형식 정의
class CustomerCreate(BaseModel):
    ID: str
    PW: str    
    NAME: str
    BIRTH: date
    ADDR: str
    EMAIL: str
    PHONE: str

# 고객 리스트 
@router.get("/", response_class=HTMLResponse)
async def get_customers_list_page(
    request: Request, 
    search_type: str = None, 
    search_value: str = None, 
    db: Session = Depends(get_db)
):  #고객 검색 
    query = db.query(models.Customer)

    if search_type and search_value:
        search_filter = f"%{search_value}%"
        if search_type == "id":
            query = query.filter(models.Customer.ID.like(search_filter))
        elif search_type == "name":
            query = query.filter(models.Customer.NAME.like(search_filter))
        elif search_type == "addr":
            query = query.filter(models.Customer.ADDR.like(search_filter))

    customers = query.all()
    
    return templates.TemplateResponse("customers.html", {
        "request": request, 
        "customers": customers,
        "search_type": search_type, 
        "search_value": search_value
    })
#고객 상세 정보
@router.get("/{member_id}", response_class=HTMLResponse)
async def get_customer_detail_page(
    request: Request, 
    member_id: str, 
    db: Session = Depends(get_db)
):
    customer = db.query(models.Customer).filter(models.Customer.ID == member_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    
    return templates.TemplateResponse("customer_detail.html", {
        "request": request, 
        "customer": customer
    })

# 고객 추가 
@router.post("/")
async def create_customer(customer: CustomerCreate, db: Session = Depends(get_db)):
    existing_user = db.query(models.Customer).filter(models.Customer.ID == customer.ID).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="이미 존재하는 아이디입니다.")

    try:
        new_customer = models.Customer(**customer.dict())
        db.add(new_customer)
        db.commit()
        db.refresh(new_customer)
        return {"message": "고객이 추가되었습니다.", "id": new_customer.ID}
    except Exception as e:
        db.rollback() 
        raise HTTPException(status_code=500, detail=f"DB 저장 실패: {str(e)}")