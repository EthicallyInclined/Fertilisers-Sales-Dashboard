import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

# ─── 1. INGESTION ────────────────────────────────────────────────────────────
df = pd.read_csv('C:\project\DataSet.csv', parse_dates=['Date'])
print(f"[1] Loaded {len(df):,} rows × {df.shape[1]} columns")

# ─── 2. DATA QUALITY REPORT ──────────────────────────────────────────────────
print("\n[2] DATA QUALITY REPORT")
print(f"  Nulls: {df.isnull().sum().sum()}")
print(f"  Duplicates: {df.duplicated('TransactionID').sum()}")
print(f"  Date range: {df.Date.min().date()} → {df.Date.max().date()}")
print(f"  Revenue negatives: {(df.Revenue < 0).sum()}")
print(f"  Return rate: {(df.ReturnFlag=='Yes').mean()*100:.1f}%")

# ─── 3. CLEANING ─────────────────────────────────────────────────────────────
df['Month_Name'] = df.Date.dt.strftime('%b')
df['YearMonth']  = df.Date.dt.to_period('M')
df_clean = df[df.ReturnFlag == 'No'].copy()
print(f"\n[3] Clean rows (excl returns): {len(df_clean):,}")

# ─── 4. SUMMARY STATISTICS ───────────────────────────────────────────────────
print("\n[4] SUMMARY STATISTICS")
kpis = {
    'Total Revenue (₹ Cr)': df_clean.Revenue.sum()/1e7,
    'Total Volume (MT)':     df_clean.Quantity_MT.sum(),
    'Avg Order Value (₹)':   df_clean.Revenue.mean(),
    'Gross Margin (%)':      (df_clean.Gross_Profit.sum()/df_clean.Revenue.sum())*100,
    'Avg Discount (%)':      df_clean.Discount_Pct.mean()*100,
    'Unique Products':       df_clean.Product.nunique(),
    'States Covered':        df_clean.State.nunique(),
    'Sales Reps':            df_clean.SalesRep.nunique(),
}
for k,v in kpis.items():
    print(f"  {k}: {v:.2f}" if isinstance(v,float) else f"  {k}: {v}")

# ─── 5. ANNUAL TREND ─────────────────────────────────────────────────────────
annual = df_clean.groupby('Year').agg(
    Revenue=('Revenue','sum'), Profit=('Gross_Profit','sum'),
    Volume=('Quantity_MT','sum'), Txns=('TransactionID','count')
).reset_index()
annual['YoY_Growth'] = annual.Revenue.pct_change()*100
annual['Margin_Pct'] = annual.Profit/annual.Revenue*100
print("\n[5] ANNUAL TREND")
print(annual.to_string(index=False))

# ─── 6. PRODUCT ANALYSIS ─────────────────────────────────────────────────────
prod = df_clean.groupby(['Product','Category']).agg(
    Revenue=('Revenue','sum'), Volume=('Quantity_MT','sum'),
    Margin=('Gross_Profit','sum'), Orders=('TransactionID','count'),
    AvgDiscount=('Discount_Pct','mean')
).reset_index()
prod['Margin_Pct'] = prod.Margin/prod.Revenue*100
prod = prod.sort_values('Revenue', ascending=False)
print("\n[6] PRODUCT SCORECARD (Top 5)")
print(prod[['Product','Category','Revenue','Volume','Margin_Pct','AvgDiscount']].head().to_string(index=False))

# ─── 7. STATE ANALYSIS ───────────────────────────────────────────────────────
state = df_clean.groupby('State').agg(
    Revenue=('Revenue','sum'), Volume=('Quantity_MT','sum'),
    Margin=('Gross_Profit','sum'), Districts=('District','nunique')
).reset_index().sort_values('Revenue', ascending=False)
state['Margin_Pct'] = state.Margin/state.Revenue*100
state['Rank'] = range(1, len(state)+1)
print("\n[7] STATE PERFORMANCE")
print(state[['Rank','State','Revenue','Volume','Margin_Pct']].to_string(index=False))

# ─── 8. SEASONAL ANALYSIS ────────────────────────────────────────────────────
seasonal = df_clean.groupby(['Season','Quarter']).agg(
    Revenue=('Revenue','sum'), Volume=('Quantity_MT','sum'),
    Txns=('TransactionID','count')
).reset_index()
print("\n[8] SEASONAL ANALYSIS")
print(seasonal.to_string(index=False))

# ─── 9. CHANNEL ANALYSIS ─────────────────────────────────────────────────────
channel = df_clean.groupby('Channel').agg(
    Revenue=('Revenue','sum'), Orders=('TransactionID','count'),
    AvgDiscount=('Discount_Pct','mean'), Profit=('Gross_Profit','sum')
).reset_index()
channel['Margin_Pct'] = channel.Profit/channel.Revenue*100
channel = channel.sort_values('Revenue', ascending=False)
print("\n[9] CHANNEL EFFICIENCY")
print(channel[['Channel','Revenue','Orders','Margin_Pct','AvgDiscount']].to_string(index=False))

# ─── 10. MONTHLY TREND ───────────────────────────────────────────────────────
monthly = df_clean.groupby(['Year','Month']).agg(
    Revenue=('Revenue','sum'), Volume=('Quantity_MT','sum')
).reset_index()

# ─── 11. CUSTOMER SEGMENT ────────────────────────────────────────────────────
cust = df_clean.groupby('CustomerType').agg(
    Revenue=('Revenue','sum'), Txns=('TransactionID','count'),
    Profit=('Gross_Profit','sum')
).reset_index()
cust['AOV'] = cust.Revenue/cust.Txns
cust['Margin_Pct'] = cust.Profit/cust.Revenue*100
cust = cust.sort_values('Revenue',ascending=False)
print("\n[10] CUSTOMER SEGMENT")
print(cust.to_string(index=False))

# ─── 12. CORRELATION ANALYSIS ────────────────────────────────────────────────
corr = df_clean[['Revenue','Quantity_MT','Unit_Price','Discount_Pct','Gross_Profit']].corr()
print("\n[11] CORRELATION MATRIX (Revenue focus)")
print(corr[['Revenue']].round(3).to_string())

# ─── 13. RETURNS ANALYSIS ────────────────────────────────────────────────────
returns = df.groupby('Product').apply(
    lambda x: pd.Series({'Total':len(x),'Returns':(x.ReturnFlag=='Yes').sum(),
                         'Return_Rate':(x.ReturnFlag=='Yes').mean()*100})
).reset_index().sort_values('Return_Rate', ascending=False)
print("\n[12] RETURN ANALYSIS BY PRODUCT")
print(returns.to_string(index=False))

# ─── EXPORT AGGREGATES ───────────────────────────────────────────────────────
aggs = {
    'Annual':   annual,
    'Products': prod,
    'States':   state,
    'Seasonal': seasonal,
    'Channel':  channel,
    'Monthly':  monthly,
    'Customer': cust,
    'Returns':  returns,
}
for name, data in aggs.items():
    data.to_csv("C:\project\DataSet.csv", index=False)
    
