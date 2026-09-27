"""Extract timestamped reference sheets and selected frames; no game assets."""
from pathlib import Path
import argparse
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
VIDEO = ROOT / 'Videos' / 'DrawRace 2 - iPhone - NZ - HD Gameplay Trailer.mp4'
OUT = ROOT / 'docs' / 'reference'

def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/arial.ttf', size)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--overview', action='store_true')
    parser.add_argument('--times', type=float, nargs='*', default=[])
    parser.add_argument('--sequence', type=float, nargs=3, metavar=('START', 'END', 'STEP'))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.overview:
        frames = OUT / 'overview_frames'
        frames.mkdir(exist_ok=True)
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(VIDEO),
                        '-vf', 'select=not(mod(n\\,150)),scale=400:300', '-fps_mode', 'vfr',
                        '-q:v', '3', str(frames / '%04d.jpg')], check=True)
        paths = sorted(frames.glob('*.jpg'))
        for start in range(0, len(paths), 16):
            sheet = Image.new('RGB', (1600, 1304), '#10151d')
            draw = ImageDraw.Draw(sheet)
            for j, path in enumerate(paths[start:start+16]):
                x, y = (j % 4)*400, (j // 4)*326
                sheet.paste(Image.open(path), (x, y+26))
                seconds = (start+j)*150*1001/30000
                draw.text((x+8, y+3), f'{int(seconds)//60:02d}:{seconds%60:04.1f}', font=font(20), fill='white')
            sheet.save(OUT / f'overview_{start//16+1:02d}.jpg', quality=90)
        print(f'{len(paths)} frames, {(len(paths)+15)//16} sheets')
    times = args.times
    if args.sequence:
        start, end, step = args.sequence
        times = [start+i*step for i in range(int((end-start)/step)+1)]
    selected = []
    for second in times:
        path = OUT / f'frame_{second:07.2f}.jpg'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(second),
                        '-i', str(VIDEO), '-frames:v', '1', '-q:v', '2', str(path)], check=True)
        selected.append((second, path))
    if args.sequence:
        for start in range(0, len(selected), 12):
            sheet = Image.new('RGB', (1440, 1384), '#10151d')
            draw = ImageDraw.Draw(sheet)
            for j, (second, path) in enumerate(selected[start:start+12]):
                x, y = (j%3)*480, (j//3)*346
                im = Image.open(path).crop((210, 200, 1230, 880)).resize((480, 320))
                sheet.paste(im, (x, y+26))
                draw.text((x+8,y+3), f'{int(second)//60:02d}:{second%60:05.2f}', font=font(20), fill='white')
            sheet.save(OUT / f'sequence_{args.sequence[0]:07.2f}_{start//12+1:02d}.jpg', quality=90)
    print(OUT)

if __name__ == '__main__':
    main()
