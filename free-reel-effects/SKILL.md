---
name: "free-reel-effects"
description: "By GALTech School of Technology (www.galtechlearning.com). Add 11 Instagram-reel style effects (glass widgets, orbit, spotlight, text-behind-person, newspaper, toggles, etc.) to a vertical video for free, fully locally with ffmpeg + Python."
---

# Free Reel Effects

Created by **GALTech School of Technology** · [www.galtechlearning.com](https://www.galtechlearning.com)

Turns any vertical (9:16) talking-head / singing / presenter clip into a fast-paced reel with up to 11 effects. Everything runs locally: no paid APIs, no credits. Person cut-out uses the free open-source `u2net_human_seg` model (ONNX), so effects like text-behind-the-person and spotlight work without paid background removal.

## Effects (names for `--effects`)

| name | what it looks like |
|---|---|
| `glass` | Frosted glass cards float in: title card, live audio bars (driven by the real audio), stat counter |
| `orbit` | Mini preview cards of the other effects circle around the person (back cards go behind them) |
| `spot` | Room goes dark, the person stays lit (follows their cut-out) |
| `behind` | Huge glowing word placed BEHIND the person's head |
| `title` | Yellow background + big "10 EDITS"-style title |
| `todo` | Dark "Editing your clip" checklist ticking off items one by one |
| `news` | Newspaper front page with masthead, highlighted headline and the video inset |
| `brief` | Orange magazine-poster layout with two video tiles and bold headline |
| `timeline` | Editing-timeline panel (clip strip, captions, grade, waveform, render bar, moving playhead) above the video |
| `toggles` | iPhone-style switches flip on one by one |
| `match` | Video dissolves into orange halftone dots and back (transition) |

Default runs all 11 in the order above, splitting the video evenly between them (minus `--intro` clean seconds at the start and `--outro` at the end).

## Requirements

- `python3`, `ffmpeg`, `curl`
- `pip install numpy opencv-python-headless pillow onnxruntime` (add `--user` or `--break-system-packages` if needed)
- Internet once for `setup` (~180 MB model + 2 Google fonts from GitHub, cached in `~/.free_reel_fx`)

## Workflow

0. **New system? Check and install requirements first.** If `python3 -c "import numpy, cv2, PIL, onnxruntime"` fails, `ffmpeg` is missing, or `~/.free_reel_fx` lacks the model/fonts:
   - If the repo is available (https://github.com/seokochin/galtech-video-effects-skill), run `bash install.sh` (Mac/Linux) or `powershell -ExecutionPolicy Bypass -File install.ps1` (Windows). It checks Python 3.9+, ffmpeg and curl, installs anything missing (Homebrew / apt / dnf / pacman / winget), installs the Python packages and runs `fx.py setup`.
   - Otherwise install by hand: ffmpeg (`brew install ffmpeg`, `sudo apt install ffmpeg`, or `winget install Gyan.FFmpeg`), then `python3 -m pip install numpy opencv-python-headless pillow onnxruntime`, then `python3 fx.py setup`.

1. **Get the input video** and ask the user (or infer from the content) for the on-screen texts. Keep them short:
   - `--title` / `--subtitle` / `--kicker` (glass title card), `--word` (giant text behind the person, 3-6 letters looks best)
   - `--count` + `--unit` (big title, e.g. "10" + "EDITS"), `--stat` + `--stat-value` (glass counter card)
   - `--brand` (newspaper name), `--headline`, `--highlight` (a word inside the headline, best a single word so it doesn't wrap), `--dek`
   - `--toggles` (exactly 3 comma-separated labels)
   - `--effects` subset/order if the user only wants some
   Stats like views/listeners are placeholders: tell the user to use real numbers or remove that card before posting publicly.
2. **Write `fx.py`** exactly as given at the bottom of this skill into a working folder (not the user's folder).
3. **Run the stages** (all are resumable):
   ```bash
   python3 fx.py setup
   python3 fx.py prep  --input "IN.mp4" --work WORK
   python3 fx.py masks --work WORK            # ~0.5 s per frame on 4 CPU cores
   python3 fx.py plan  --work WORK [--effects ...]   # shows which effect lands where
   python3 fx.py render --work WORK [text options]
   python3 fx.py concat --work WORK --output "OUT.mp4"
   ```
   Or one shot on a normal computer: `python3 fx.py all --input IN.mp4 --output OUT.mp4 --work WORK [text options]`.
4. **Time-limited shells (e.g. Cowork device shell ~180 s per call, background jobs get killed):**
   - Masks: repeat `python3 fx.py masks --work WORK --seconds 160` until it prints `MASKS DONE`.
   - Render in frame chunks, e.g. `--from 0 --to 325`, `--from 325 --to 650`, ... (each chunk writes `seg_<from>.mp4`; ~15-45 s per 325 frames). Use the SAME text options for every chunk, then run `concat`.
   - Delete old `seg_*.mp4` in WORK before re-rendering with different settings.
5. **Verify**: grab a still from the middle of each effect (`plan` gives the times) with `ffmpeg -ss T -i OUT.mp4 -frames:v 1 x.jpg`, look at them, fix text that overlaps badly, re-render only the affected chunk, re-concat.
6. **Deliver** the final MP4 next to the user's original file, with a short summary of the effect timeline.

## Notes

- Input is auto cover-cropped to 720x1280 @ 25 fps; audio is kept. Best with one person, framed waist-up, head in the upper third.
- Fonts are Latin only (Montserrat, Playfair Display). For Malayalam/Arabic/etc. text, download a matching Noto font and swap it into `font()`.
- No word-by-word captions are generated (needs a transcript); add them separately if wanted.
- Free alternative to paid cloud effects: costs 0 credits; only CPU time.

## fx.py

```python
#!/usr/bin/env python3
"""Free reel effects: 11 Instagram-style effects on a vertical talking-head/singing clip.
Created by GALTech School of Technology · www.galtechlearning.com
Stages (all resumable, safe to run in short chunks):
  python3 fx.py setup                      # download free models + fonts (~180 MB, once)
  python3 fx.py prep   --input in.mp4 --work DIR
  python3 fx.py masks  --work DIR [--seconds 160]    # repeat until it prints MASKS DONE
  python3 fx.py render --work DIR [--from N --to M]  # or render whole video
  python3 fx.py concat --work DIR --output out.mp4
  python3 fx.py all    --input in.mp4 --output out.mp4 --work DIR   # everything in one go
Text options (render): --title --subtitle --word --count --brand --headline --highlight --toggles --stat --effects
"""
import argparse, os, sys, math, json, subprocess, time, glob
import numpy as np
HOME=os.path.expanduser('~'); MODELS=os.path.join(HOME,'.free_reel_fx')
W_,H_,FPS=720,1280,25
URLS={'u2net_human_seg.onnx':'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net_human_seg.onnx',
 'Montserrat.ttf':'https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf',
 'PlayfairDisplay.ttf':'https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf'}
ALL=['glass','orbit','spot','behind','title','todo','news','brief','timeline','toggles','match']
def sh(cmd): subprocess.run(cmd,check=True)
def setup():
    os.makedirs(MODELS,exist_ok=True)
    for n,u in URLS.items():
        p=os.path.join(MODELS,n)
        if not os.path.exists(p) or os.path.getsize(p)<1000:
            print('downloading',n,flush=True); sh(['curl','-sSfL','-o',p,u])
    print('SETUP DONE')
def prep(a):
    os.makedirs(os.path.join(a.work,'masks'),exist_ok=True)
    vf=f'scale={W_}:{H_}:force_original_aspect_ratio=increase,crop={W_}:{H_},fps={FPS}'
    sh(['ffmpeg','-v','error','-y','-i',a.input,'-vf',vf,'-c:v','libx264','-crf','16','-preset','fast','-c:a','aac','-b:a','192k',os.path.join(a.work,'src.mp4')])
    print('PREP DONE')
def masks(a):
    import cv2, onnxruntime as ort
    s=ort.InferenceSession(os.path.join(MODELS,'u2net_human_seg.onnx'),providers=['CPUExecutionProvider'])
    cap=cv2.VideoCapture(os.path.join(a.work,'src.mp4')); i=0; t0=time.time()
    while True:
        ok,f=cap.read()
        if not ok: break
        p=os.path.join(a.work,'masks',f'{i:05d}.png')
        if not os.path.exists(p):
            if time.time()-t0>a.seconds: print('MASKS PARTIAL',i,'- run again'); return
            x=cv2.resize(cv2.cvtColor(f,cv2.COLOR_BGR2RGB),(320,320)).astype(np.float32)/255
            x=(x-[0.485,0.456,0.406])/[0.229,0.224,0.225]
            o=s.run(None,{s.get_inputs()[0].name:x.transpose(2,0,1)[None].astype(np.float32)})[0][0,0]
            o=(o-o.min())/(o.max()-o.min()+1e-6)
            cv2.imwrite(p,(cv2.resize(o,(360,640))*255).astype('uint8'))
        i+=1
    print('MASKS DONE',i)

# ---------------------------------------------------------------- effects
def build(a):
    import cv2
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    SRC=os.path.join(a.work,'src.mp4')
    def font(n,size,var):
        f=ImageFont.truetype(os.path.join(MODELS,n),size)
        try: f.set_variation_by_name(var)
        except Exception: pass
        return f
    FB=lambda s,v='Bold': font('Montserrat.ttf',s,v); FS=lambda s,v='Bold': font('PlayfairDisplay.ttf',s,v)
    raw=subprocess.run(['ffmpeg','-v','error','-i',SRC,'-ac','1','-ar','8000','-f','s16le','-'],capture_output=True).stdout
    au=np.frombuffer(raw,np.int16).astype(np.float32)/32768; spf=8000//FPS; n=max(1,len(au)//spf)
    rms=np.array([np.sqrt(np.mean(au[i*spf:(i+1)*spf]**2)) if len(au[i*spf:(i+1)*spf]) else 0 for i in range(n)]); rms=rms/(np.percentile(rms,98)+1e-6)
    def lvl(i,k=0): j=min(max(i-k,0),len(rms)-1); return float(min(rms[j],1.2))
    def ease(x): x=min(max(x,0),1); return 1-(1-x)**3
    def rr_mask(w,h,r):
        m=Image.new('L',(w,h),0); ImageDraw.Draw(m).rounded_rectangle([0,0,w-1,h-1],r,fill=255); return m
    def glass(base,x,y,w,h,al=1.0,r=34):
        x,y=int(x),int(y)
        if al<=0.01: return
        crop=base.crop((x,y,x+w,y+h)).filter(ImageFilter.GaussianBlur(18)); crop=Image.blend(crop,Image.new('RGB',(w,h),(255,255,255)),0.55)
        shd=Image.new('L',(w+60,h+60),0); ImageDraw.Draw(shd).rounded_rectangle([30,40,w+30,h+40],r,fill=int(70*al)); shd=shd.filter(ImageFilter.GaussianBlur(16))
        base.paste(Image.new('RGB',shd.size,(0,0,0)),(x-30,y-30),shd); base.paste(crop,(x,y),rr_mask(w,h,r).point(lambda v:int(v*al)))
        ImageDraw.Draw(base,'RGBA').rounded_rectangle([x,y,x+w-1,y+h-1],r,outline=(255,255,255,int(200*al)),width=2)
    def mask_at(i):
        p=os.path.join(a.work,'masks',f'{i:05d}.png')
        if not os.path.exists(p): p=sorted(glob.glob(os.path.join(a.work,'masks','*.png')))[-1]
        m=cv2.resize(cv2.imread(p,0),(W_,H_)); m=cv2.GaussianBlur(m,(9,9),0); return m.astype(np.float32)/255
    head=[None]
    def head_pos(m):
        ys,xs=np.where(m>0.5)
        if len(ys)==0: return head[0] or (W_/2,300)
        top=ys.min(); sel=ys<top+160; hx,hy=xs[sel].mean(),top+120
        if head[0] is None: head[0]=(hx,hy)
        head[0]=(head[0][0]*0.85+hx*0.15,head[0][1]*0.85+hy*0.15); return head[0]
    def read_frame(i):
        c=cv2.VideoCapture(SRC); c.set(cv2.CAP_PROP_POS_FRAMES,i); ok,f=c.read(); c.release(); return cv2.cvtColor(f,cv2.COLOR_BGR2RGB)
    def fit(img,w,h,cy=0.42):
        ih,iw=img.shape[:2]; s=max(w/iw,h/ih); r=cv2.resize(img,(int(iw*s+1),int(ih*s+1)))
        y0=int(max(0,min(r.shape[0]-h,r.shape[0]*cy-h/2))); x0=(r.shape[1]-w)//2; return r[y0:y0+h,x0:x0+w]
    def paste_round(base,arr,x,y,r=26,al=1.0,shadow=True):
        im=Image.fromarray(np.clip(arr,0,255).astype(np.uint8)); w,h=im.size
        if shadow:
            shd=Image.new('L',(w+60,h+60),0); ImageDraw.Draw(shd).rounded_rectangle([30,42,w+30,h+42],r,fill=int(90*al)); shd=shd.filter(ImageFilter.GaussianBlur(14))
            base.paste(Image.new('RGB',shd.size,(0,0,0)),(int(x)-30,int(y)-30),shd)
        base.paste(im,(int(x),int(y)),rr_mask(w,h,r).point(lambda v:int(v*al)))
    def person_over(bg,img,m): mm=m[...,None]; return bg*(1-mm)+img.astype(np.float32)*mm
    def check(d,cx,cy,s,col,A): d.line([(cx-s*0.45,cy),(cx-s*0.1,cy+s*0.35),(cx+s*0.5,cy-s*0.35)],fill=col+(A,),width=max(3,int(s*0.18)),joint='curve')
    PINK=(233,84,140)
    def eff_glass(img,m,i,t,k):
        base=Image.fromarray(img); a1,a2,a3=[ease((t-d)/0.6)*k for d in (0,0.4,0.8)]; bob=lambda ph:8*math.sin(t*1.6+ph)
        x,y=28-(1-a1)*80,70+bob(0); glass(base,x,y,320,165,a1); d=ImageDraw.Draw(base,'RGBA'); A=int(255*a1)
        d.ellipse([x+28,y+30,x+44,y+46],fill=PINK+(A,)); d.text((x+54,y+24),a.kicker,font=FB(24,'Medium'),fill=(80,80,80,A))
        d.text((x+28,y+64),a.title,font=FB(40),fill=(25,25,25,A)); d.text((x+28,y+110),a.subtitle,font=FB(24,'Medium'),fill=(60,60,60,A))
        x,y=W_-280+(1-a2)*80,80+bob(1.5); glass(base,x,y,252,200,a2); d=ImageDraw.Draw(base,'RGBA'); A=int(255*a2)
        d.text((x+24,y+20),'Live audio',font=FB(24,'Medium'),fill=(60,60,60,A))
        for b in range(11):
            bh=int(14+lvl(i,b*2)*100); bx=x+24+b*20; d.rounded_rectangle([bx,y+170-bh,bx+12,y+170],5,fill=PINK+(A,))
        x,y=W_-310+(1-a3)*80,1050+bob(3); glass(base,x,y,282,160,a3); d=ImageDraw.Draw(base,'RGBA'); A=int(255*a3)
        d.text((x+24,y+20),a.stat,font=FB(24,'Medium'),fill=(60,60,60,A)); d.text((x+24,y+60),a.stat_value,font=FB(64,'ExtraBold'),fill=PINK+(A,))
        return np.array(base).astype(np.float32)
    YY,XX=np.mgrid[0:H_,0:W_].astype(np.float32)
    def eff_spot(img,m,i,t,k):
        f=img.astype(np.float32); g=f.mean(axis=2,keepdims=True); dark=(f*0.35+g*0.65)*0.16; lit=np.clip(f*1.05+[6,2,-4],0,255)
        hx,hy=head_pos(m); glow=np.exp(-(((XX-hx)/260)**2+((YY-hy-250)/520)**2))[...,None]; dark=dark+glow*f*0.22
        mm=np.clip(m*1.05,0,1)[...,None]; return f*(1-k)+(dark*(1-mm)+lit*mm)*k
    def eff_behind(img,m,i,t,k):
        f=img.astype(np.float32); hx,hy=head_pos(m); bg=f*0.45
        txt=Image.new('L',(W_,H_),0); d=ImageDraw.Draw(txt); fb=FS(250 if len(a.word)<=5 else int(1250/len(a.word)),'Black')
        while d.textlength(a.word,font=fb)>W_-40: fb=FS(fb.size-6,'Black')
        tw=d.textlength(a.word,font=fb); ty=int(hy-200); d.text(((W_-tw)/2,ty),a.word,font=fb,fill=255)
        al=ease(t/0.8)*k; sc=1.15-0.15*ease(t/0.8); tl=np.array(txt).astype(np.float32)/255
        tl=cv2.warpAffine(tl,cv2.getRotationMatrix2D((W_/2,ty+120),0,sc),(W_,H_)); glow=cv2.GaussianBlur(tl,(0,0),18)
        bg=bg+glow[...,None]*np.array([255,70,150],np.float32)*1.6*al; bg=bg*(1-tl[...,None]*al)+tl[...,None]*np.array([255,236,244])*al
        return f*(1-k)+person_over(np.clip(bg,0,255),img,m)*k
    def eff_title(img,m,i,t,k):
        al=ease(t/0.4); out=person_over(np.zeros_like(img,np.float32)+np.array([255,210,0],np.float32),img,m)
        im=Image.fromarray(np.clip(out,0,255).astype(np.uint8)); d=ImageDraw.Draw(im); sc=0.8+0.2*al
        for txt,fo,y in [(a.count,FB(int(260*sc),'Black'),700),(a.unit,FB(int(130*sc if len(a.unit)<=5 else 650/len(a.unit)*sc),'Black'),700+250*sc)]:
            tw=d.textlength(txt,font=fo); d.text(((W_-tw)/2,y),txt,font=fo,fill=(15,15,15),stroke_width=8,stroke_fill=(255,210,0))
        return img*(1-k)+np.array(im).astype(np.float32)*k
    TODO=['Found your face','Cut you out of the room','Put the text behind you','Graded the colour','Rendered in full HD']
    def eff_todo(img,m,i,t,k):
        base=Image.fromarray(img).convert('RGBA'); al=ease(t/0.5)*k; x,y,w,h=50,800+(1-al)*80,620,90+len(TODO)*58
        ov=Image.new('RGBA',base.size,(0,0,0,0)); d=ImageDraw.Draw(ov); A=int(255*al)
        d.rounded_rectangle([x,y,x+w,y+h],30,fill=(18,18,20,int(225*al))); d.ellipse([x+30,y+32,x+48,y+50],fill=(217,119,87,A))
        d.text((x+62,y+24),'Editing your clip',font=FB(30,'SemiBold'),fill=(255,255,255,A))
        done=sum(1 for j in range(len(TODO)) if t>0.7+j*0.6); d.text((x+w-95,y+28),f'{done} of {len(TODO)}',font=FB(26,'Medium'),fill=(160,160,160,A))
        for j,item in enumerate(TODO):
            yy=y+90+j*58; on=ease((t-0.7-j*0.6)/0.25); cx,cy=x+48,yy+18
            if on>0: d.ellipse([cx-16,cy-16,cx+16,cy+16],fill=(52,199,89,int(A*on))); check(d,cx,cy,22,(255,255,255),int(A*on))
            if on<1: d.ellipse([cx-16,cy-16,cx+16,cy+16],outline=(120,120,120,int(A*(1-on))),width=3)
            d.text((x+82,yy+2),item,font=FB(26,'Medium'),fill=(255,255,255,int(A*(0.55+0.45*on))))
        base.alpha_composite(ov); return np.array(base.convert('RGB')).astype(np.float32)
    def wrap(d,text,fo,maxw):
        lines,cur=[],''
        for w in text.split():
            t2=(cur+' '+w).strip()
            if d.textlength(t2,font=fo)<=maxw: cur=t2
            else: lines.append(cur); cur=w
        return lines+[cur]
    def eff_news(img,m,i,t,k):
        al=ease(t/0.6); im=Image.new('RGB',(W_,H_),(244,239,228)); d=ImageDraw.Draw(im); ink=(20,20,20); off=int((1-al)*60)
        fr=FS(20,'Regular'); d.text((40,60+off),time.strftime('%A, %B ')+str(time.localtime().tm_mday)+time.strftime(', %Y'),font=fr,fill=ink); tw=d.textlength('Late Edition',font=fr); d.text((W_-40-tw,60+off),'Late Edition',font=fr,fill=ink)
        d.line([40,92+off,W_-40,92+off],fill=ink,width=2); fm=FS(92,'Black')
        while d.textlength(a.brand,font=fm)>W_-80: fm=FS(fm.size-4,'Black')
        tw=d.textlength(a.brand,font=fm); d.text(((W_-tw)/2,100+off),a.brand,font=fm,fill=ink)
        d.line([40,222+off,W_-40,222+off],fill=ink,width=2); d.line([40,228+off,W_-40,228+off],fill=ink,width=1)
        secs='WORLD   LOCAL   MUSIC   CULTURE   ARTS'; fs=FS(18,'Bold'); tw=d.textlength(secs,font=fs); d.text(((W_-tw)/2,240+off),secs,font=fs,fill=ink)
        d.line([40,272+off,W_-40,272+off],fill=ink,width=1); d.text((40,300+off),'THE NEW EDIT',font=FS(22,'Bold'),fill=(150,30,30))
        fh=FS(56,'Bold'); y=340+off
        for ln in wrap(d,a.headline,fh,W_-80)[:4]:
            x=40
            if a.highlight and a.highlight in ln:
                pre=ln[:ln.index(a.highlight)]; hx=x+d.textlength(pre,font=fh); pw=d.textlength(a.highlight,font=fh); hl=ease((t-0.8)/0.4)
                d.rectangle([hx-4,y+8,hx-4+(pw+8)*hl,y+66],fill=(255,226,80))
            d.text((x,y),ln,font=fh,fill=ink); y+=70
        d.text((40,y+14),a.dek,font=FS(26,'Regular'),fill=(70,70,70))
        vid=fit(img,640,int(H_-(y+70)-60)); g=vid.mean(axis=2,keepdims=True); vid=(vid*0.6+g*0.4)*np.array([1.02,0.98,0.9])
        im.paste(Image.fromarray(np.clip(vid,0,255).astype(np.uint8)),(40,int(y+70))); return img*(1-k)+np.array(im).astype(np.float32)*k
    cache={}
    def read_cache(i):
        j=max(0,i-50)
        if j not in cache: cache.clear(); cache[j]=read_frame(j)
        return cache[j]
    def eff_brief(img,m,i,t,k):
        im=Image.new('RGB',(W_,H_),(240,84,45)); d=ImageDraw.Draw(im)
        d.rectangle([0,70,430,170],fill=(15,15,15)); d.text((28,80),'THE BRIEF',font=FB(72,'Black'),fill=(255,255,255))
        d.text((452,88),'EXCLUSIVE',font=FB(30,'ExtraBold'),fill=(255,255,255)); d.text((452,124),'PERFORMANCE',font=FB(30,'ExtraBold'),fill=(255,255,255))
        im.paste(Image.fromarray(fit(img,330,420).astype(np.uint8)),(20,200)); im.paste(Image.fromarray(fit(read_cache(i),330,420).astype(np.uint8)),(370,200))
        fb=FB(96,'Black'); y=650; lines=[f'{a.count} EDITS'.upper(),'DONE BY','AI IN','ONE GO']
        for j,txt in enumerate(lines):
            s=ease((t-0.2-j*0.15)/0.3); x=24-int((1-s)*700)
            if j==3: tw=d.textlength(txt,font=fb); d.rectangle([x-6,y+10,x+tw+6,y+108],fill=(255,226,80))
            d.text((x,y),txt,font=fb,fill=(15,15,15)); y+=104
        d.rectangle([24,y+24,520,y+74],fill=(15,15,15)); d.text((40,y+32),'"never opened an editor"',font=FB(28,'SemiBold'),fill=(255,255,255))
        return img*(1-k)+np.array(im).astype(np.float32)*k
    strip=[None]
    def eff_timeline(img,m,i,t,k):
        if strip[0] is None:
            dur=cv2.VideoCapture(SRC).get(cv2.CAP_PROP_FRAME_COUNT)/FPS
            strip[0]=[cv2.resize(fit(read_frame(int(j*FPS)),90,120),(44,58)) for j in np.linspace(0.5,max(1,dur-1),11)]
        al=ease(t/0.5); im=Image.new('RGB',(W_,H_),(239,231,220)); d=ImageDraw.Draw(im)
        f1=FB(52,'ExtraBold'); f2=FS(54,'Regular'); w1=d.textlength('Watch it ',font=f1); w2=d.textlength('render',font=f2); x=(W_-w1-w2)/2
        d.text((x,40),'Watch it ',font=f1,fill=(20,20,20)); d.text((x+w1,36),'render',font=f2,fill=(160,60,120))
        px,py,pw,ph=24,130+(1-al)*40,672,330; d.rounded_rectangle([px,py,px+pw,py+ph],22,fill=(42,22,58))
        for j,c in enumerate([(255,95,87),(255,189,46),(155,120,255)]): d.ellipse([px+22+j*20,py+20,px+34+j*20,py+32],fill=c)
        d.text((px+100,py+15),(a.word+'  ·  RENDER').upper(),font=FB(20,'SemiBold'),fill=(230,220,255)); x0=px+130; xw=pw-150
        for j,r in enumerate(['V1 CLIP','CAPTIONS','GRADE','AUDIO','RENDER']):
            yy=py+60+j*52; d.text((px+20,yy+12),r,font=FB(17,'SemiBold'),fill=(200,190,230))
            if j==0:
                for q,s in enumerate(strip[0]): im.paste(Image.fromarray(s.astype(np.uint8)),(int(x0+q*48),int(yy-6)))
            elif j==1:
                for q,lab in enumerate([a.word.lower(),a.title.lower()[:10],f'{a.count} edits']):
                    xx=x0+[0,150,330][q]; d.rounded_rectangle([xx,yy+4,xx+140,yy+36],6,fill=(255,140,190)); d.text((xx+10,yy+8),lab,font=FB(18,'SemiBold'),fill=(60,20,40))
            elif j==2:
                d.rounded_rectangle([x0,yy+4,x0+300,yy+36],6,fill=(140,70,220)); d.text((x0+10,yy+8),'warm base',font=FB(18,'SemiBold'),fill=(240,230,255))
                d.rounded_rectangle([x0+310,yy+4,x0+xw,yy+36],6,fill=(110,60,190)); d.text((x0+320,yy+8),'spotlight',font=FB(18,'SemiBold'),fill=(240,230,255))
            elif j==3:
                for q in range(70):
                    v=lvl(int(q*len(rms)/70)); bh=4+v*26; xx=x0+q*(xw/70); d.line([xx,yy+20-bh/2,xx,yy+20+bh/2],fill=(220,210,240),width=3)
            else:
                pr=min(1,t/3.5); d.rounded_rectangle([x0,yy+12,x0+xw,yy+28],8,fill=(80,50,100)); d.rounded_rectangle([x0,yy+12,x0+xw*pr,yy+28],8,fill=(255,110,180))
        phx=x0+xw*min(1,t/3.5); d.line([phx,py+50,phx,py+ph-20],fill=(255,110,180),width=3)
        paste_round(im,fit(img,672,H_-int(py+ph)-50,0.4),24,int(py+ph)+24,28,1.0,False); return img*(1-k)+np.array(im).astype(np.float32)*k
    TOG=[(s.strip(),c) for s,c in zip(a.toggles.split(','),[(255,159,10),(52,199,89),(175,82,222)])]
    def eff_toggles(img,m,i,t,k):
        base=Image.fromarray(img); al=ease(t/0.6)*k; x0,y0=60,830+(1-al)*120; w,h=600,96
        glass(base,x0,y0,w,h*len(TOG)+20,al,r=30); d=ImageDraw.Draw(base,'RGBA'); A=int(255*al)
        for j,(lab,c) in enumerate(TOG):
            y=y0+10+j*h
            if j: d.line([x0+100,y,x0+w-30,y],fill=(0,0,0,int(30*al)),width=1)
            d.rounded_rectangle([x0+28,y+22,x0+80,y+74],12,fill=c+(A,)); cx,cy=x0+54,y+48
            if j==0: d.ellipse([cx-11,cy-11,cx+11,cy+11],fill=(255,255,255,A))
            elif j==1: d.polygon([(cx,cy+14),(cx-14,cy-2),(cx-7,cy-12),(cx,cy-5),(cx+7,cy-12),(cx+14,cy-2)],fill=(255,255,255,A))
            else: d.polygon([(cx+14*math.cos(math.pi/2+q*math.pi/5)*(1 if q%2==0 else .45),cy-14*math.sin(math.pi/2+q*math.pi/5)*(1 if q%2==0 else .45)) for q in range(10)],fill=(255,255,255,A))
            d.text((x0+102,y+30),lab,font=FB(30,'SemiBold'),fill=(20,20,20,A))
            on=ease((t-1.0-j*0.9)/0.35); tx,ty=x0+w-130,y+26
            bgc=tuple(int(v) for v in np.array([210,210,215])*(1-on)+np.array([52,199,89])*on)
            d.rounded_rectangle([tx,ty,tx+92,ty+46],23,fill=bgc+(A,)); kx=tx+4+on*46; d.ellipse([kx,ty+4,kx+38,ty+42],fill=(255,255,255,A))
        return np.array(base).astype(np.float32)
    thumbs=[None]
    def eff_orbit(img,m,i,t,k):
        if thumbs[0] is None:
            j=min(200,int(cv2.VideoCapture(SRC).get(cv2.CAP_PROP_FRAME_COUNT))-1); fr=read_frame(j); mm=mask_at(j); saved=head[0]; head[0]=None; head_pos(mm); out=[]
            for lab,fn,tt in [('GLASS UI',eff_glass,3),('SPOTLIGHT',eff_spot,3),(a.word,eff_behind,3),(f'{a.count} EDITS',eff_title,3),('SWITCHES',eff_toggles,5),('TODO',eff_todo,5),('NEWS',eff_news,3),('THE BRIEF',eff_brief,3)]:
                th=Image.fromarray(cv2.resize(np.clip(fn(fr,mm,j,tt,1),0,255).astype(np.uint8),(130,231))); d=ImageDraw.Draw(th)
                f=FB(20,'Black'); tw=d.textlength(lab,font=f); d.text(((130-tw)/2,170),lab,font=f,fill=(255,255,255),stroke_width=3,stroke_fill=(0,0,0))
                b=Image.new('RGB',(136,237),(255,255,255)); b.paste(th,(3,3)); out.append(np.array(b))
            thumbs[0]=out; head[0]=saved
        hx,hy=head_pos(m); al=ease(t/0.6)*k; cx,cy=hx,hy+300; rx,ry=290*al+40,90
        back=Image.fromarray(img); front=Image.fromarray(img); N=len(thumbs[0])
        for depth,nn,ang in sorted([(math.sin(t*0.9+q*2*math.pi/N),q,t*0.9+q*2*math.pi/N) for q in range(N)]):
            s=0.62+0.28*(depth+1)/2; w,h=int(136*s),int(237*s); x=cx+rx*math.cos(ang)-w/2; y=cy+ry*depth-h/2
            paste_round(back if depth<0 else front,cv2.resize(thumbs[0][nn],(w,h)),x,y,12,al)
        b=np.array(back).astype(np.float32); f=np.array(front).astype(np.float32); base=person_over(b,img,m)
        diff=(np.abs(f-img.astype(np.float32)).sum(axis=2,keepdims=True)>3).astype(np.float32); return base*(1-diff)+f*diff
    def halftone(img,cell):
        g=cv2.cvtColor(img.astype(np.uint8),cv2.COLOR_RGB2GRAY).astype(np.float32)/255; out=np.zeros_like(img,np.uint8); out[:]=(244,239,228)
        sm=cv2.resize(g,(W_//cell,H_//cell),interpolation=cv2.INTER_AREA)
        for yy in range(sm.shape[0]):
            for xx in range(sm.shape[1]):
                r=(1-sm[yy,xx])*cell*0.62
                if r>0.8: cv2.circle(out,(xx*cell+cell//2,yy*cell+cell//2),int(r),(222,95,60),-1,lineType=cv2.LINE_AA)
        return out.astype(np.float32)
    def eff_match(img,m,i,t,k,D=4.0):
        p=t/a._seglen; amt=ease(p/0.35) if p<0.5 else ease((1-p)/0.35); return img*(1-amt)+halftone(img,int(10+12*amt))*amt
    return dict(glass=eff_glass,orbit=eff_orbit,spot=eff_spot,behind=eff_behind,title=eff_title,todo=eff_todo,news=eff_news,brief=eff_brief,timeline=eff_timeline,toggles=eff_toggles,match=eff_match),mask_at,head_pos,ease

def timeline(a,dur):
    effs=[e.strip() for e in a.effects.split(',') if e.strip()]
    start,end=a.intro,max(a.intro+1,dur-a.outro); L=(end-start)/len(effs); a._seglen=L
    return [(start+j*L,start+(j+1)*L,e) for j,e in enumerate(effs)]
SOFT={'spot','behind','title','news','brief','timeline'}
def render(a):
    import cv2
    SRC=os.path.join(a.work,'src.mp4'); total=int(cv2.VideoCapture(SRC).get(cv2.CAP_PROP_FRAME_COUNT)); dur=total/FPS
    TL=timeline(a,dur); EFF,mask_at,head_pos,ease=build(a)
    A0=a.frm or 0; A1=min(a.to or total,total); out=os.path.join(a.work,f'seg_{A0:06d}.mp4')
    cap=cv2.VideoCapture(SRC); cap.set(cv2.CAP_PROP_POS_FRAMES,A0)
    ff=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W_}x{H_}','-r',str(FPS),'-i','-','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',out],stdin=subprocess.PIPE)
    if A0>0: head_pos(mask_at(A0-1))
    i=A0
    while i<A1:
        ok,fr=cap.read()
        if not ok: break
        img=cv2.cvtColor(fr,cv2.COLOR_BGR2RGB); T=i/FPS; o=img.astype(np.float32)
        for s,e,name in TL:
            if s<=T<e:
                k=min(ease((T-s)/0.25),ease((e-T)/0.25)) if name in SOFT else 1.0
                o=EFF[name](img,mask_at(i),i,T-s,k)
        ff.stdin.write(np.clip(o,0,255).astype(np.uint8).tobytes()); i+=1
    ff.stdin.close(); ff.wait(); print('RENDERED',A0,i,'of',total)
def concat(a):
    segs=sorted(glob.glob(os.path.join(a.work,'seg_*.mp4'))); lst=os.path.join(a.work,'list.txt')
    open(lst,'w').write(''.join(f"file '{s}'\n" for s in segs))
    sh(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',lst,'-i',os.path.join(a.work,'src.mp4'),'-map','0:v','-map','1:a?','-c:v','copy','-c:a','aac','-b:a','192k','-shortest',a.output]); print('SAVED',a.output)
def main():
    p=argparse.ArgumentParser(); p.add_argument('stage',choices=['setup','prep','masks','render','concat','all','plan'])
    p.add_argument('--input'); p.add_argument('--output'); p.add_argument('--work',default=os.path.join(HOME,'reel_fx_work'))
    p.add_argument('--seconds',type=float,default=1e9); p.add_argument('--from',dest='frm',type=int); p.add_argument('--to',type=int)
    p.add_argument('--effects',default=','.join(ALL)); p.add_argument('--intro',type=float,default=0.0); p.add_argument('--outro',type=float,default=3.0)
    p.add_argument('--kicker',default='NOW PLAYING'); p.add_argument('--title',default='My Video'); p.add_argument('--subtitle',default='Edited with AI')
    p.add_argument('--word',default='WOW'); p.add_argument('--count',default='10'); p.add_argument('--unit',default='EDITS'); p.add_argument('--stat',default='Views'); p.add_argument('--stat-value',dest='stat_value',default='12.4K')
    p.add_argument('--brand',default='The Daily Reel'); p.add_argument('--headline',default='One clip, ten edits: AI takes over the edit')
    p.add_argument('--highlight',default='AI'); p.add_argument('--dek',default='A single clip, edited by AI.'); p.add_argument('--toggles',default='Good lighting,Main character,Edited by AI')
    a=p.parse_args(); a.word=a.word.upper(); a.work=os.path.abspath(a.work); a.output=os.path.abspath(a.output) if a.output else None; os.makedirs(a.work,exist_ok=True)
    if a.stage=='setup': return setup()
    if a.stage=='prep': return prep(a)
    if a.stage=='masks': return masks(a)
    if a.stage=='plan':
        import cv2; total=int(cv2.VideoCapture(os.path.join(a.work,'src.mp4')).get(7))
        for s,e,n in timeline(a,total/FPS): print(f'{s:6.1f}-{e:6.1f}s  {n}')
        return
    if a.stage=='render': return render(a)
    if a.stage=='concat': return concat(a)
    if a.stage=='all':
        setup(); prep(a); masks(a); [os.remove(f) for f in glob.glob(os.path.join(a.work,'seg_*.mp4'))]; render(a); concat(a)
if __name__=='__main__': main()
```
