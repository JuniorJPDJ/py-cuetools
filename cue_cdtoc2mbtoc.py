#!/usr/bin/env python3
from typing import List
import os, io, base64, hashlib

import mutagen
import chardet


SECTORS_PER_SECOND = 75
SAMPLES_PER_SECTOR = 588

def _parse_cue_line(line: str):
	line = line.strip()
	words = []
	word = ""
	quote = False
	for x in line:
		if x == '"':
			quote = not quote
		elif x == ' ' and not quote:
			if word:
				words.append(word)
			word = ""
		else:
			word += x
	if word:
		words.append(word)
	return words

def _cue_time_to_sector(time: str):
	minutes, seconds, frames = [int(x) for x in time.split(':')]
	return (minutes*60 + seconds)*75 + frames

def from_cue(cue: str):
	toc = []

	# http://wiki.hydrogenaud.io/index.php?title=Cue_sheet
	# https://web.archive.org/web/20160201021136/http://digitalx.org/cue-sheet/syntax/#track
	track_counter = 0
	sector_counter = 150
	last_file_sector = 0
	last_track_num = None
	last_track_type = None
	
	file = None
	
	def _close_file():
		nonlocal sector_counter
		if file is not None:
			sector_counter += round(file.info.length * SECTORS_PER_SECOND) - last_file_sector

	print("PARSING CUE DATA")
	
	for l in cue.splitlines():
		l = _parse_cue_line(l)
		if not l:
			continue
		if l[0] == "FILE":
			_close_file()
			last_file_sector = 0
			file = mutagen.File(l[1])
		elif l[0] in ("PREGAP", "POSTGAP"):
			sector_counter += _cue_time_to_sector(l[1])
		elif l[0] == "INDEX" and l[1] == "01":
			file_sector = _cue_time_to_sector(l[2])
			sector_counter += file_sector - last_file_sector
			last_file_sector = file_sector
			toc.append(sector_counter if last_track_type == "AUDIO" else -sector_counter)
			track_counter += 1
		elif l[0] == "TRACK":
			last_track_num = l[1]
			last_track_type = l[2]
		elif l[0] == "ISRC":
			print(last_track_num, l[1])
	_close_file()
	toc.append(sector_counter)
	
	return toc

def from_cdtoc(cdtoc: str):
	# https://github.com/gchudov/cuetools.net/blob/5f7b450b47e455a501b82b5e81308be168e4949f/CUETools.CDImage/CDImage.cs#L442
	print("CDTOC:",cdtoc)
	toc = [int(x, 16) if x[0] != 'X' else -int(x[1:], 16) for x in cdtoc.split('+')]
	audio_tracks = toc.pop(0)

	for track in range(audio_tracks, len(toc) - 1 - sum(1 for x in toc if x < 0)):
		# between last audio and end sector
		# [audio_tracks=2 track1 track2 end -datatrack -datatrack] when data tracks are inside
		# [audio_tracks=2 track1 track2 datatrack end] when at end
		toc[track] *= -1

	return sorted(toc, key=abs)

def track_sec(toc: List, num: int):
	# enumerated from 0
	start = toc[num]
	end = toc[num+1] if toc[num+1] > 0 else -toc[num+1] - 11400

	return abs(start), abs(end)

def mb_toc(toc: List):
	toc = toc.copy()
	last_audio = len(toc) - 1
	for track in reversed(toc[:-1]):
		if track >= 0:
			break
		last_audio -= 1

	#end_sector = toc[last_audio] if toc[last_audio] > 0 else -toc[last_audio] - 11400
	end_sector = track_sec(toc, last_audio-1)[1]
	# data track at end (Enhanced CD) - musicbrainz skips them

	yield 1
	yield last_audio
	yield end_sector
	for track in range(last_audio):
		yield abs(toc[track])
	
def ctdb_toc(toc: List):
	for x in toc:
		if x == -150:
			yield "-0"
		else:
			yield str(x - 150 if x > 0 else x + 150)

def ctdb_tocid(toc: List):
	# https://github.com/gchudov/db.cue.tools/blob/master/phpctdb/ctdb.php#L199
	# https://github.com/gchudov/db.cue.tools/blob/master/phpctdb/ctdb.php#L129
	x = ""

	for first_audio, sec in enumerate(toc):
		if sec > 0:
			break
	
	audio_tracks = sum(1 for x in toc if x > 0) - 1

	pregap = toc[first_audio]
	for tr in range(first_audio+1, first_audio + audio_tracks):
		x += f"{abs(toc[tr]) - pregap:08X}"
	leadout = track_sec(toc, first_audio + audio_tracks - 1)[1]
	x += f"{leadout - pregap:08X}"

	return base64.b64encode(hashlib.sha1(x.ljust(800, '0').encode()).digest()).decode('ascii').replace('+', '.').replace('/', '_').replace('=', '-')
	

def mb_url(toc: List):
	return "https://musicbrainz.org/bare/cdlookup.html?toc="+"+".join(str(x) for x in mb_toc(toc))

def ctdb_lookup_url(toc: List):
	return "http://db.cuetools.net/lookup2.php?version=3&ctdb=1&metadata=extensive&fuzzy=1&toc="+":".join(ctdb_toc(toc))

def ctdb_url(toc: list):
	return "http://db.cuetools.net/?tocid=" + ctdb_tocid(toc)

def main(fname):
	if fname.endswith('.cue'):
		with open(fname, 'rb') as f:
			cue = f.read()
		
		cue = cue.decode(chardet.detect(cue).get("encoding"))
		
		dir = os.path.dirname(fname)
		if dir:
			os.chdir(dir)
		toc = from_cue(cue)
	else:  
		f = mutagen.File(fname)
		if "CDTOC" in f:
			toc = from_cdtoc(f['CDTOC'][0])
		elif "CUESHEET" in f:
			os.chdir(os.path.dirname(fname))
			cue = f['cuesheet'][0]
			toc = from_cue(cue)
		else:
			print("Found no usable content table")
			return
	print("TOC:", " ".join(str(x) for x in toc))
	print("MusicBrainZ:", mb_url(toc))
	print("CUETools DB:", ctdb_url(toc))
	print("CUETools DB lookup:", ctdb_lookup_url(toc))

if __name__ == "__main__":
	import sys
	main(*sys.argv[1:])

