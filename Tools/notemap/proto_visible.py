import re, sys, glob, unicodedata, collections
JOSA = sorted("""은 는 이 가 을 를 의 에 에서 에게 께 께서 한테 으로 로 으로서 로서 으로써 로써 와 과 랑 이랑 하고 도 만 까지 부터 마저 조차 보다 처럼 같이 만큼 이나 나 이나마 나마 이든 든 이라도 라도 이란 란 이라 라 이라는 라는 에는 에도 에서는 에서도 으로는 로는 으로도 로도 과는 와는 이며 며 이고 고 께는 에게는 에게도 한테는 까지는 부터는 만은 이야 야 인 들 들이 들은 들을 들의 들에 들도 들과""".split(), key=len, reverse=True)
STOP=set("""그리고 그러나 하지만 그래서 그런데 또는 및 등 것 수 때 곳 중 더 안 못 잘 좀 다 또 이 그 저 이런 그런 저런 이것 그것 저것 여기 거기 오늘 어제 내일 지금 이번 다음 우리 나 너 저희 제 내 했다 한다 하는 있다 없다 된다 되는 하고 하면 해서 있는 없는 같은 위해 대한 통해 때문 경우 정도 이상 이하 뒤 앞 위 아래 하나 둘 셋 모두 각 매 몇 어떤 무엇 왜 어디 언제 누가""".split())
TOKEN=re.compile(r"[0-9A-Za-z가-힣][0-9A-Za-z가-힣_\-]*")
VERBEND=re.compile(r"(했다|한다|된다|있다|없다|하는|되는|하고|해서|하면|했고|합니다|입니다|습니다|ㅂ니다|이다|였다|었다|았다|겠다|하기|하여|해야|하지|되어|되지|되면|된|할|한|하게|스럽|롭게|적으로)$")
def strip(tok):
    if re.fullmatch(r"[A-Za-z0-9_\-]+",tok): return tok.lower()
    m=re.match(r"^([A-Za-z0-9]+)([가-힣]+)$",tok)
    if m: return m.group(1).lower()
    for j in JOSA:
        if tok.endswith(j) and len(tok)-len(j)>=2:
            return tok[:-len(j)]
    return tok
def visible(text):
    lines=text.split("\n"); out=[]; i=0
    if lines and lines[0].strip()=="---":
        for k in range(1,len(lines)):
            if lines[k].strip() in("---","..."): i=k+1;break
    fence=None; comment=False
    for l in lines[i:]:
        s=l.strip()
        if comment:
            if "-->" in l: comment=False
            continue
        if s.startswith("<!--"):
            if "-->" not in s: comment=True
            continue
        if re.match(r"^ {0,3}(```|~~~)",l):
            fence = None if fence else s[:3]; continue
        if fence: continue
        l=re.sub(r"!?\[([^\]]*)\]\([^)]*\)",r"\1",l)
        l=re.sub(r"https?://\S+","",l); l=re.sub(r"`[^`]*`","",l)
        out.append(l)
    return "\n".join(out)
def keywords(text):
    ks=set()
    for t in TOKEN.findall(unicodedata.normalize("NFC",visible(text))):
        if VERBEND.search(t): continue
        k=strip(t)
        if len(k)<2 or k in STOP or k.isdigit(): continue
        if re.fullmatch(r"[a-z]{1,2}",k): continue
        ks.add(k)
    return ks
if __name__=="__main__":
  c=collections.Counter()
  files=glob.glob(sys.argv[1])
  for f in files: c.update(keywords(open(f,encoding='utf-8').read()))
  print(len(files),"files")
  print(" · ".join(f"{k}({n})" for k,n in c.most_common(60)))
