# 329 · 330 노트 지도 설계 때의 시제품 (2026-11-26) — 착수 전 규칙 시험용. 심판이 아니다: 착수하면 Tools/golden/note_map.py 가 원본이 된다.
# 쓰는 법: python3 Tools/notemap/prototype.py "docs/**/*.md"  (문서마다 git 의 마지막 고친 날을 노트 날짜로 본다)
import re, sys, glob, unicodedata, collections, math, subprocess, datetime, os
sys.path.insert(0,'.')
from proto_visible import visible, TOKEN
JOSA = sorted("""은 는 이 가 을 를 의 에 에서 에게 께 께서 한테 으로 로 으로서 로서 와 과 이랑 랑 하고 도 만 까지 부터 마저 조차 보다 처럼 만큼 이나 나 이든 이라도 라도 이란 이라는 라는 에는 에도 에서는 에서도 으로는 로는 으로도 로도 과는 와는 이며 에게는 까지는 부터는 만은 이야 들 들이 들은 들을 들의 들에 들도 들과 들로""".split(), key=len, reverse=True)
STOP=set("""그리고 그러나 하지만 그래서 그런데 또는 및 등 것 수 때 곳 중 더 안 못 잘 좀 다 또 이 그 저 이런 그런 저런 이것 그것 저것 여기 거기 오늘 어제 내일 지금 이번 다음 우리 저희 그대로 다시 바로 아직 이미 먼저 모두 함께 같이 정말 너무 아주 매우 가장 계속 항상 위해 대한 통해 때문 경우 정도 이상 이하 하나 어떤 무엇 에서 으로 부터 까지 처럼 아니면 경우""".split())
BADSTEM=re.compile(r"(는다|[있없했됐였었았겠한된간온본준갔왔봤줬]다|[않많좋같없있]아|해|워|져|려|하|되|했|됐|있|없|겠|였|었|았|시|지|게|고|면|서|며|니|까|요|죠|네|던|든|랑|이|히)$")
def forms(text):
    out=[]
    for t in TOKEN.findall(unicodedata.normalize("NFC",visible(text))):
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9_\-]*",t): out.append((t.lower(),"")); continue
        m=re.match(r"^([A-Za-z][A-Za-z0-9]*)([가-힣]+)$",t)
        if m: out.append((m.group(1).lower(),"+")); continue
        if not re.search("[가-힣]",t): continue
        cand=[(t,"")]
        for j in JOSA:
            if t.endswith(j):
                if len(t)-len(j)>=2: cand.append((t[:-len(j)],j))
                break
        out.append(cand)
    return out
def build(notes):
    seen=collections.defaultdict(set)
    per=[]
    for text in notes:
        fs=forms(text); per.append(fs)
        for f in fs:
            if isinstance(f,tuple): seen[f[0]].add(f[1] or "∅")
            else:
                for s,j in f: seen[s].add(j or "∅")
    def ok(s):
        if len(s)<2 or s in STOP: return False
        if re.fullmatch(r"[a-z][a-z0-9_\-]*",s): return len(s)>=3
        return len(seen[s])>=2 and not BADSTEM.search(s)
    res=[]
    for fs in per:
        ks=set()
        for f in fs:
            if isinstance(f,tuple):
                if ok(f[0]): ks.add(f[0])
            else:
                stem=[s for s,j in f if j]
                if stem and ok(stem[0]): ks.add(stem[0])
                elif ok(f[0][0]): ks.add(f[0][0])
        res.append(ks)
    return res
files=glob.glob(sys.argv[1],recursive=True)
texts=[open(f,encoding='utf-8').read() for f in files]
dates=[]
for f in files:
    d=subprocess.run(["git","-C","/home/user/MD_Management","log","-1","--format=%cs","--",f],capture_output=True,text=True).stdout.strip()
    dates.append(datetime.date.fromisoformat(d))
kws=build(texts)
N=len(files); df=collections.Counter(k for ks in kws for k in ks)
today=datetime.date(2026,11,26)
for days in (28,90):
    cur=collections.Counter(); prev=collections.Counter(); ncur=0
    for ks,d in zip(kws,dates):
        age=(today-d).days
        if age<days: cur.update(ks); ncur+=1
        elif age<2*days: prev.update(ks)
    score={k:n*math.log((N+1)/(df[k])) for k,n in cur.items() if n>=2}
    top=sorted(score,key=lambda k:-score[k])[:30]
    print(f"\n최근 {days}일 · 노트 {ncur}개")
    print(" · ".join(f"{k}{cur[k]}{'↑' if cur[k]>prev[k] else ''}" for k in top))
print("\n전체 많이 나온 순:", " · ".join(f"{k}{n}" for k,n in df.most_common(30)))

def neighbors(center, days=28, k=6):
    sel=[ks for ks,d in zip(kws,dates) if (today-d).days<days and center in ks]
    co=collections.Counter(x for ks in sel for x in ks if x!=center)
    sc={x:n*math.log((N+1)/df[x]) for x,n in co.items() if n>=2}
    return len(sel), sorted(sc,key=lambda x:-sc[x])[:k], co
for c in ("명조","pdf","자판"):
    n,top,co=neighbors(c)
    print(f"[{c}] 노트 {n}개 → "+" · ".join(f"{x}{co[x]}" for x in top))
