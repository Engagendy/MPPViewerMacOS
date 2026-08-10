import base64, subprocess, os
RAW="marketing/raw"; OUT="marketing/shots"; VAR="marketing/shots/variants"
os.makedirs(OUT, exist_ok=True); os.makedirs(VAR, exist_ok=True)
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
def b64(p): return base64.b64encode(open(p,'rb').read()).decode()
ICON=b64(f"{RAW}/icon.png")

BG=("radial-gradient(1200px 900px at 84% 4%, rgba(255,255,255,.10), transparent 60%),"
    "radial-gradient(1500px 1100px at 6% 106%, __ACCENT__33, transparent 55%),"
    "linear-gradient(135deg,#070b1a 0%,#101736 50%,#1b2a63 100%)")

BRAND=('<div class=brand><span class=chip><img src="data:image/png;base64,'+ICON+'"></span>'
       '<span class=word>Planroom</span></div>')

CSS="""*{margin:0;padding:0;box-sizing:border-box}
html,body{width:2880px;height:1800px;overflow:hidden;font-family:-apple-system,'SF Pro Display','Helvetica Neue',Arial,sans-serif}
.bg{position:absolute;inset:0;background:__BG__}
.brand{display:flex;align-items:center;gap:26px}
.chip{width:104px;height:104px;border-radius:25px;background:#fff;display:flex;align-items:center;justify-content:center;box-shadow:0 14px 36px rgba(0,0,0,.45)}
.chip img{width:86px;height:86px;border-radius:19px}
.word{color:#fff;font-size:46px;font-weight:600;letter-spacing:.4px;opacity:.97}
h1{color:#fff;font-weight:800;letter-spacing:-1.2px}
.accentbar{height:11px;border-radius:8px;background:__ACCENT__}
p.sub{color:#e6ecff;opacity:.84;font-weight:400}
.shot{border:1px solid rgba(255,255,255,.16);box-shadow:0 46px 130px rgba(0,0,0,.6),0 0 0 1px rgba(0,0,0,.25)}
""".replace("__BG__",BG)

TOP="<!doctype html><html><head><meta charset=utf-8><style>"+CSS+"""
.wrap{position:relative;width:100%;height:100%;padding:96px 160px 0}
.brand{margin-bottom:54px}
h1{font-size:92px;line-height:1.08;max-width:2560px;white-space:nowrap}
.accentbar{width:140px;margin:30px 0 0}
p.sub{font-size:46px;margin-top:28px;max-width:2300px;white-space:nowrap}
.shot{position:absolute;left:50%;transform:translateX(-50%);bottom:0;width:1980px;border-radius:24px 24px 0 0;border-bottom:none}
</style></head><body><div class=bg></div><div class=wrap>__BRAND__
<h1>__HEAD__</h1><div class=accentbar></div><p class=sub>__SUB__</p></div>
<img class=shot src="data:image/png;base64,__SHOT__"></body></html>"""

SIDE="<!doctype html><html><head><meta charset=utf-8><style>"+CSS+"""
.brand{position:absolute;left:150px;top:104px}
.left{position:absolute;left:150px;top:0;bottom:0;width:1220px;display:flex;flex-direction:column;justify-content:center}
h1{font-size:104px;line-height:1.06;max-width:1200px}
.accentbar{width:150px;margin:40px 0 0}
p.sub{font-size:48px;margin-top:34px;max-width:1120px}
.shot{position:absolute;right:-140px;top:50%;transform:translateY(-50%);width:1620px;border-radius:26px}
</style></head><body><div class=bg></div>__BRAND__
<img class=shot src="data:image/png;base64,__SHOT__">
<div class=left><h1>__HEAD__</h1><div class=accentbar></div><p class=sub>__SUB__</p></div>
</body></html>"""

def render(tpl,name,head,sub,accent,shotfile,folder=OUT):
    shot=b64(f"{RAW}/{shotfile}.png")
    htmls=(tpl.replace("__BRAND__",BRAND).replace("__HEAD__",head).replace("__SUB__",sub)
              .replace("__ACCENT__",accent).replace("__SHOT__",shot))
    hpath=f"{folder}/{name}.html"; open(hpath,'w').write(htmls)
    outp=os.path.abspath(f"{folder}/{name}.png")
    subprocess.run([CHROME,"--headless","--disable-gpu","--hide-scrollbars","--force-device-scale-factor=1",
        "--window-size=2880,1800",f"--screenshot={outp}","file://"+os.path.abspath(hpath)],capture_output=True)
    os.remove(hpath); print("rendered",folder.split('/')[-1]+"/"+name)

frames=[
 ("01_gantt","Holidays, events &amp; leave — on one timeline","Toggle overlays to see every intersection with your schedule.","#3b82f6","01_gantt"),
 ("02_planbuilder","A keyboard-first plan builder","Copy, paste, insert and reorder rows — or paste from Excel.","#8b5cf6","02_planbuilder"),
 ("03_workload","Balance workload with leave in view","Spot over-allocation and time off at a single glance.","#f59e0b","03_workload"),
 ("04_events","Plan holidays, events &amp; resource leave","A dedicated timeline with live editing and PDF / SVG export.","#ec4899","04_events"),
 ("05_resources","Manage staffing, rates &amp; capacity","See each person's peak load and catch over-allocation early.","#14b8a6","12_resources"),
 ("06_agileboard","Run delivery on a Kanban board","Backlog to done, with sprints, buckets and workflow.","#6366f1","14_agileboard"),
 ("07_criticalpath","Keep an eye on the critical path","Driving tasks, float and near-critical work, ranked.","#ef4444","13_criticalpath"),
 ("08_earnedvalue","Track schedule &amp; earned value","EVM metrics, an S-curve and baselines — built in.","#06b6d4","07_earnedvalue"),
 ("09_milestones","Track milestones and health","Dates, variance and status for every key checkpoint.","#22c55e","11_milestones"),
 ("10_executive","Brief stakeholders in one view","Progress, risks and major milestones, summarized.","#a855f7","16_executive"),
]
for n,h,s,a,f in frames: render(TOP,n,h,s,a,f)
render(TOP ,"heroA_top","Holidays, events &amp; leave — on one timeline","Toggle overlays to see every intersection with your schedule.","#3b82f6","01_gantt",VAR)
render(SIDE,"heroB_side","See holidays &amp; leave beside your schedule","Overlay company holidays, events and per-person time off on the Gantt.","#3b82f6","01_gantt",VAR)
render(TOP ,"heroC_alt","Plan around holidays, events &amp; time off","Every conflict, visible before it becomes a delay.","#f59e0b","01_gantt",VAR)
