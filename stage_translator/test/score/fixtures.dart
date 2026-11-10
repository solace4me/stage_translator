// test/score/fixtures.dart
// Small made-up scores shared by the score tests.

// A tiny made-up hymn in F (one flat), 4/4, grand staff, four voices.
// Bar 1: S = F G A B-natural with two verses; bar 2 changes to C major:
// S = C5 half tied to a quarter, then a rest.
const kHymn = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <work><work-title>Test Hymn</work-title></work>
  <identification><creator type="composer">Anon</creator></identification>
  <part-list><score-part id="P1"><part-name>Hymn</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>-1</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
      </attributes>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><stem>up</stem><staff>1</staff>
        <lyric number="1"><syllabic>single</syllabic><text>Sing</text></lyric>
        <lyric number="2"><syllabic>single</syllabic><text>Praise</text></lyric></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><stem>up</stem><staff>1</staff>
        <lyric number="1"><syllabic>single</syllabic><text>a</text></lyric>
        <lyric number="2"><syllabic>single</syllabic><text>the</text></lyric></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><stem>up</stem><staff>1</staff>
        <lyric number="1"><syllabic>begin</syllabic><text>ho</text></lyric>
        <lyric number="2"><syllabic>single</syllabic><text>Lord</text></lyric></note>
      <note><pitch><step>B</step><alter>0</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><stem>up</stem><staff>1</staff>
        <lyric number="1"><syllabic>end</syllabic><text>ly</text></lyric>
        <lyric number="2"><syllabic>single</syllabic><text>now</text></lyric></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><voice>2</voice><stem>down</stem><staff>1</staff></note>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><voice>2</voice><stem>down</stem><staff>1</staff></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration><voice>2</voice><stem>down</stem><staff>1</staff></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration><voice>2</voice><stem>down</stem><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>A</step><octave>3</octave></pitch><duration>2</duration><voice>5</voice><stem>up</stem><staff>2</staff></note>
      <note><pitch><step>B</step><alter>-1</alter><octave>3</octave></pitch><duration>2</duration><voice>5</voice><stem>up</stem><staff>2</staff></note>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><voice>5</voice><stem>up</stem><staff>2</staff></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration><voice>5</voice><stem>up</stem><staff>2</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>F</step><octave>3</octave></pitch><duration>4</duration><voice>6</voice><stem>down</stem><staff>2</staff></note>
      <note><pitch><step>B</step><alter>-1</alter><octave>2</octave></pitch><duration>4</duration><voice>6</voice><stem>down</stem><staff>2</staff></note>
    </measure>
    <measure number="2">
      <attributes><key><fifths>0</fifths></key></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><tie type="start"/><voice>1</voice><stem>up</stem><staff>1</staff></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><tie type="stop"/><voice>1</voice><stem>up</stem><staff>1</staff></note>
      <note><rest/><duration>2</duration><voice>1</voice><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>8</duration><voice>2</voice><stem>down</stem><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>8</duration><voice>5</voice><stem>up</stem><staff>2</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration><voice>6</voice><stem>down</stem><staff>2</staff></note>
    </measure>
  </part>
</score-partwise>''';

// The same idea written the way many hymn files are: soprano + alto as
// chords in one voice on staff 1, tenor + bass as chords on staff 2.
// Chord notes listed bottom-up, no stems, no part names.
const kChordHymn = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><key><fifths>1</fifths></key><staves>2</staves></attributes>
      <note><pitch><step>B</step><octave>3</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
        <lyric number="1"><text>Hal</text><syllabic>begin</syllabic></lyric></note>
      <note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff></note>
      <note><chord/><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff></note>
      <backup><duration>2</duration></backup>
      <note><pitch><step>G</step><octave>2</octave></pitch><duration>1</duration><voice>5</voice><staff>2</staff></note>
      <note><chord/><pitch><step>D</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><staff>2</staff></note>
      <note><pitch><step>D</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><staff>2</staff></note>
      <note><chord/><pitch><step>A</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><staff>2</staff></note>
    </measure>
  </part>
</score-partwise>''';

// A made-up tune in G major, 6/8, for beams and slurs.
// Bar 1: six eighths G A B C D E, slur over the first three.
// Bar 2: dotted-quarter D, sixteenths E F#, eighth G, eighth rest.
const kBeamTune = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Soprano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>4</divisions><key><fifths>1</fifths></key><time><beats>6</beats><beat-type>8</beat-type></time></attributes>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><notations><slur type="start" number="1"/></notations></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><notations><slur type="stop" number="1"/></notations></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice></note>
    </measure>
    <measure number="2">
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>6</duration><voice>1</voice><dot/></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>F</step><alter>1</alter><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><rest/><duration>2</duration><voice>1</voice></note>
    </measure>
  </part>
</score-partwise>''';

// A made-up tune in C, 4/4, for repeats and lyric hold lines:
// |: C D E F | [1. G :| [2. A | C' ||
// "Joy" is held over C, D and E (an extender line), then "to" on F.
const kRepeatTune = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Soprano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <barline location="left"><repeat direction="forward"/></barline>
      <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice>
        <lyric number="1"><syllabic>single</syllabic><text>Joy</text><extend/></lyric></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice>
        <lyric number="1"><syllabic>single</syllabic><text>to</text></lyric></note>
    </measure>
    <measure number="2">
      <barline location="left"><ending number="1" type="start"/></barline>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice>
        <lyric number="1"><syllabic>single</syllabic><text>all</text></lyric></note>
      <barline location="right"><ending number="1" type="stop"/><repeat direction="backward"/></barline>
    </measure>
    <measure number="3">
      <barline location="left"><ending number="2" type="start"/></barline>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice>
        <lyric number="1"><syllabic>single</syllabic><text>men</text></lyric></note>
      <barline location="right"><ending number="2" type="discontinue"/></barline>
    </measure>
    <measure number="4">
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>''';

// An alto line with one short divided passage (a two-note chord), like
// bars 30-31 of "Lift Every Voice and Sing". It must stay one voice.
const kDivisiAlto = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Alto</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
    </measure>
    <measure number="2">
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice></note>
    </measure>
  </part>
</score-partwise>''';
