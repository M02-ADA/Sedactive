"""Rebuild native vector artwork and small, locally synthesized game cues."""
from pathlib import Path
import json, math, struct, wave
root = Path(__file__).resolve().parent.parent / 'FamilyMove/Resources/Assets.xcassets'
art = {
'MoleIllustration': '''<svg xmlns="http://www.w3.org/2000/svg" width="300" height="280" viewBox="0 0 300 280">
<ellipse cx="150" cy="248" rx="118" ry="17" fill="#C49674" opacity=".22"/>
<path d="M42 237 Q25 215 58 205 Q60 185 91 195 Q117 180 151 192 Q181 178 209 197 Q241 190 247 211 Q279 218 256 240 Q152 263 42 237Z" fill="#79513C"/>
<circle cx="93" cy="82" r="26" fill="#A7704E"/><circle cx="209" cy="82" r="26" fill="#A7704E"/>
<circle cx="93" cy="82" r="16" fill="#E8B5A0"/><circle cx="209" cy="82" r="16" fill="#E8B5A0"/>
<path d="M69 212 Q56 163 80 104 Q103 51 151 57 Q207 55 226 111 Q246 172 230 218 Q164 248 69 212Z" fill="#B7835B"/>
<ellipse cx="151" cy="192" rx="53" ry="41" fill="#E9BC88"/>
<path d="M79 182 Q44 156 49 184 Q33 166 36 190 Q19 181 31 208 Q49 231 80 218Z" fill="#A56E49"/>
<path d="M224 181 Q259 153 255 180 Q273 164 269 188 Q286 178 275 205 Q254 230 224 217Z" fill="#A56E49"/>
<ellipse cx="121" cy="121" rx="11" ry="15" fill="#34281F"/><ellipse cx="183" cy="121" rx="11" ry="15" fill="#34281F"/>
<ellipse cx="118" cy="116" rx="3.5" ry="5" fill="#FFF8EB"/><ellipse cx="180" cy="116" rx="3.5" ry="5" fill="#FFF8EB"/>
<ellipse cx="103" cy="147" rx="13" ry="8" fill="#D89A82"/><ellipse cx="201" cy="147" rx="13" ry="8" fill="#D89A82"/>
<path d="M139 140 Q151 132 164 140 Q163 151 151 155 Q140 150 139 140Z" fill="#5B392C"/>
<path d="M138 162 Q152 177 167 162" fill="none" stroke="#5B392C" stroke-width="4" stroke-linecap="round"/>
<path d="M66 232 Q151 252 238 232" fill="none" stroke="#684431" stroke-width="8" stroke-linecap="round"/>
</svg>''',
'BirdIllustration': '''<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240">
<ellipse cx="155" cy="214" rx="103" ry="10" fill="#9FB6BF" opacity=".18"/>
<path d="M113 165 L97 197 L133 192 M166 174 L156 206 L191 199" fill="#E5A14E" stroke="#E5A14E" stroke-width="8" stroke-linejoin="round"/>
<path d="M75 136 L37 111 L56 162 L90 171" fill="#607B8A"/>
<path d="M58 154 Q78 105 134 113 Q165 118 196 105 Q226 110 220 145 Q213 190 151 192 Q88 196 58 154Z" fill="#F5EDDC"/>
<path d="M93 140 Q125 116 176 146 Q155 189 107 171 Q92 165 93 140Z" fill="#A9B4B0"/>
<path d="M109 143 Q140 134 162 150" fill="none" stroke="#7F9795" stroke-width="7" stroke-linecap="round"/>
<path d="M183 123 Q183 99 196 85 Q184 45 211 34 Q246 16 259 48 Q270 80 244 94 L242 136 Q208 158 183 123Z" fill="#4E967E"/>
<path d="M189 120 Q214 136 242 120 L243 138 Q212 154 188 133Z" fill="#F6E9D2"/>
<path d="M257 64 Q298 58 302 74 Q295 90 256 83Z" fill="#E9AC55"/>
<circle cx="242" cy="58" r="7" fill="#233E38"/><circle cx="244" cy="56" r="2.5" fill="#FFF8EB"/>
<path d="M216 39 Q223 33 230 35" fill="none" stroke="#6CAC96" stroke-width="5" stroke-linecap="round"/>
<path d="M58 75 Q77 63 91 74 M32 93 L67 93" stroke="#A8C6CF" stroke-width="5" fill="none" stroke-linecap="round"/>
</svg>''',
'AlligatorIllustration': '''<svg xmlns="http://www.w3.org/2000/svg" width="340" height="240" viewBox="0 0 340 240">
<ellipse cx="172" cy="218" rx="145" ry="12" fill="#9BAF8C" opacity=".19"/>
<path d="M226 148 Q284 125 313 81 Q318 147 272 176Z" fill="#6C9F79"/>
<path d="M111 152 Q112 104 178 108 Q240 107 264 155 L268 184 Q241 210 167 206 Q109 202 111 152Z" fill="#6CA383"/>
<path d="M136 114 L147 94 L162 110 L178 87 L193 109 L210 93 L223 117" fill="#4D7E62"/>
<path d="M131 183 L103 214 L147 214 L162 187 M220 185 L214 216 L261 213 L243 182" fill="#53866A"/>
<path d="M81 104 Q59 77 77 62 Q97 42 117 67 Q140 49 159 65 Q180 83 164 108Z" fill="#77AC84"/>
<path d="M57 98 Q17 107 23 137 Q28 163 80 169 L169 160 Q192 139 168 114Z" fill="#7EB38C"/>
<path d="M31 132 Q73 154 147 135 L175 142 Q116 184 52 164Z" fill="#405E4D"/>
<path d="M40 140 L49 152 L58 144 L68 157 L78 148 L89 158 L99 147 L111 153 L120 141 L133 146 L142 137" fill="#FFF3D8"/>
<path d="M42 163 Q102 182 153 155" fill="none" stroke="#93BF8E" stroke-width="13" stroke-linecap="round"/>
<ellipse cx="92" cy="81" rx="7" ry="9" fill="#253E35"/><ellipse cx="139" cy="83" rx="7" ry="9" fill="#253E35"/>
<circle cx="90" cy="78" r="2.5" fill="#FFF8E8"/><circle cx="137" cy="80" r="2.5" fill="#FFF8E8"/>
<circle cx="44" cy="115" r="3.5" fill="#477257"/><circle cx="58" cy="112" r="3.5" fill="#477257"/>
<ellipse cx="166" cy="177" rx="24" ry="13" fill="#A9C696"/>
<circle cx="206" cy="144" r="7" fill="#55896E"/><circle cx="225" cy="160" r="5" fill="#55896E"/>
</svg>'''}
for name, svg in art.items():
    folder = root / (name + '.imageset'); folder.mkdir(exist_ok=True)
    (folder / (name + '.svg')).write_text(svg)
    (folder / 'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.svg','idiom':'universal'}], 'info':{'author':'xcode','version':1}, 'properties':{'preserves-vector-representation':True}}, indent=2)+'\n')

# No downloaded audio or microphone input; short sine envelopes mixed locally.
cues = {'Countdown': [(523.25, 0.13)], 'Success': [(659.25, .10), (880, .17)],
        'Complete': [(523.25, .12), (659.25, .12), (783.99, .12), (1046.5, .28)]}
for name, notes in cues.items():
    folder = root / (name + 'Sound.dataset'); folder.mkdir(exist_ok=True)
    samples = []
    for hz, duration in notes:
        length = int(22050 * duration)
        for idx in range(length):
            envelope = min(1, idx / 180) * max(0, 1 - idx / length) ** 1.4
            samples.append(int(9000 * math.sin(2 * math.pi * hz * idx / 22050) * envelope))
        samples.extend([0] * 400)
    with wave.open(str(folder / 'cue.wav'), 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(22050)
        audio.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
    (folder / 'Contents.json').write_text(json.dumps({'data':[{'filename':'cue.wav','idiom':'universal'}], 'info':{'author':'xcode','version':1}}, indent=2)+'\n')
print('Generated 3 vector illustrations and 3 short game cues.')
