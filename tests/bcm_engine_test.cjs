// Tests for the Automatic WBS Classification engine (ProTrackAI v3.35), run with Node 18+:
//   node bcm_engine_test.cjs ../live.html /path/to/xlsx.js > results_bcm_engine.json
// The engine is taken from the page itself (between BCM-ENGINE-BEGIN and BCM-ENGINE-END), so what is tested is what ships.
// xlsx.js is SheetJS 0.18.5, the version the app loads (git clone --depth 1 --branch v0.18.5 https://github.com/SheetJS/sheetjs).
// The workbooks are tests/fixtures/bcm (made by make_fixtures.py; all test data).
const fs = require('fs'), path = require('path'), vm = require('vm');
const [page, sjs] = process.argv.slice(2);
const html = fs.readFileSync(page, 'utf8');
const a = html.indexOf('/* BCM-ENGINE-BEGIN'), b = html.indexOf('/* BCM-ENGINE-END */');
if (a < 0 || b < 0) { console.error('engine block not found'); process.exit(2); }
const sandbox = { module: { exports: {} }, console };
vm.runInNewContext(html.slice(a, b) + '\nmodule.exports=BCME;', sandbox);
const E = sandbox.module.exports, X = require(path.resolve(sjs));
const FX = path.join(__dirname, 'fixtures', 'bcm');
const R = [], ck = (area, name, cond, detail) => { R.push({ area, check: name, result: cond ? 'PASS' : 'FAIL', detail: cond ? '' : JSON.stringify(detail ?? '').slice(0, 300) }); console.error((cond ? 'PASS ' : 'FAIL ') + area + ': ' + name + (cond ? '' : '  -> ' + JSON.stringify(detail ?? '').slice(0, 300))); };
const read = f => { const u = new Uint8Array(fs.readFileSync(path.join(FX, f))); const c = E.checkFile(f, u); if (!c.ok) return { check: c }; const r = E.readBook(X, u); return r.error ? { check: c, error: r.error } : { check: c, book: E.extractBook(r.wb, X) }; };
const items = bk => bk.sheets.flatMap(s => s.lines.filter(l => l.kind === 'item'));
const appr = L => L.map(x => ({ ...x, cur: JSON.parse(JSON.stringify(x.pend.data)), ver: 1, pend: null, status: 'Approved' }));
const W0 = appr(E.seedWbs()), R0 = appr(E.seedRules());
const ctxOf = o => E.context(Object.assign({ wbs: W0, rules: R0, maps: [], cfg: E.SEED_CFG, date: '2026-10-23', ptype: '132 kV substation', pid: 'P1' }, o || {}));
const cls = (l, o, over) => E.classify(l, ctxOf(o), over);
const find = (bk, re) => items(bk).find(l => re.test(l.desc));

// ---------------- money
ck('Money', 'decimals are exact: 0.1 + 0.2 = 0.3, and 1,234.565 is kept to the last place', E.decStr(E.dec(0.1) + E.dec(0.2)) === '0.3' && E.decStr(E.dec('1,234.565')) === '1234.565');
ck('Money', 'accounting negatives (1,000.00) and trailing minus are read as negative', E.decStr(E.dec('(1,000.00)')) === '-1000' && E.decStr(E.dec('250-')) === '-250');
ck('Money', 'currency precision: SAR 2 places, KWD 3 places, half-up', E.money('1234.565', 'SAR') === '1,234.57' && E.money('1.2345', 'KWD') === '1.235');
ck('Money', 'text that is not a number is never turned into zero', E.dec('n/a') === null && E.dec('') === null && E.dec('1,23') === null);

// ---------------- files
ck('Files', 'a text file named .xlsx is refused before reading, with the reason', /not an Excel workbook/.test((read('12_not_a_workbook.xlsx').check || {}).error || ''), read('12_not_a_workbook.xlsx').check);
ck('Files', 'CSV and .xlsb are refused with what to do', /save it as \.xlsx/.test(E.checkFile('a.csv', new Uint8Array([1])).error) && /\.xlsb/.test(E.checkFile('a.xlsb', new Uint8Array([1])).error));
ck('Files', 'an empty file is refused', /empty/.test(E.checkFile('a.xlsx', new Uint8Array(0)).error));
ck('Files', 'a file over 25 MB is refused', /25 MB/.test(E.checkFile('a.xlsx', new Uint8Array(E.MAX_BYTES + 1)).error));
const xls = read('01_simple.xls'), xlsx = read('01_simple.xlsx'), xlsm = read('02_multi_sheet.xlsm');
ck('Files', '.xls (Excel 97-2003) is read like .xlsx: the same lines and amounts', xls.book && JSON.stringify(items(xls.book).map(l => [l.row, l.desc, l.amount])) === JSON.stringify(items(xlsx.book).map(l => [l.row, l.desc, l.amount])));
ck('Files', '.xlsm is read as data only (macros never run), with every sheet', xlsm.check.macro === true && xlsm.book && xlsm.book.sheets.length === 3 && items(xlsm.book).length === 10);

// ---------------- extraction
const b1 = xlsx.book;
const rebar = find(b1, /rebar Grade 60/);
ck('Extraction', 'a simple sheet: six cost lines with quantity, unit, rate and amount', items(b1).length === 6 && rebar.qty === '120' && rebar.unit === 'ton' && rebar.unit_n === 't' && rebar.rate === '3200' && rebar.amount === '384000', rebar);
ck('Extraction', 'each line keeps its sheet, row and cell references, and its original text', rebar.sheet === 'Costing' && rebar.row === 2 && rebar.desc_ref === 'B2' && rebar.amount_ref === 'F2' && rebar.desc === 'Supply of rebar Grade 60');
ck('Extraction', 'an amount from a formula keeps the formula and says so', rebar.amount_src === 'formula' && rebar.f === '=C2*E2');
ck('Extraction', 'the grand total row is recognised and becomes the control total, not a cost line', b1.sheets[0].lines.find(l => l.row === 8).kind === 'total' && b1.control && b1.control.amount === '6572300' && b1.control.ref === 'F8');
const b2 = read('02_multi_sheet.xlsx').book;
ck('Extraction', 'header rows are found where they are (row 4, row 3, row 1), with other column names', b2.sheets.map(s => s.header.row).join() === '4,3,1' && b2.sheets[1].header.names.desc === 'Scope' && b2.sheets[1].header.names.amount === 'Extended Price');
ck('Extraction', 'title rows above the header are not taken as cost lines', !b2.sheets[0].lines.some(l => /TENDER T-2026-118/.test(l.desc || '')));
const b3 = read('03_hidden_merged.xlsx').book;
ck('Extraction', 'a hidden sheet is read and marked hidden', b3.sheets[1].hidden === true && /Hidden sheet/.test(b3.sheets[1].warnings[0]) && items(b3).some(l => l.hidden_sheet && /Engineering hours/.test(l.desc)));
ck('Extraction', 'a two-row header under a merged heading ("Price" over Rate and Amount) maps rate and amount to their own columns', b3.sheets[0].header.cols.rate === 'E' && b3.sheets[0].header.cols.amount === 'F', b3.sheets[0].header);
ck('Extraction', 'a merged section heading becomes the section of the lines below it', find(b3, /Commissioning of 132kV/).secs[0] === 'A. TESTING AND COMMISSIONING' && b3.sheets[0].lines.find(l => l.row === 4).kind === 'section');
const b4 = read('04_formula_subtotals.xlsx').book, L4 = b4.sheets[0].lines;
ck('Extraction', 'formula subtotals (SUM over the rows above) and the grand total are detected, never counted as cost lines', L4.filter(l => l.kind === 'subtotal').map(l => l.row).join() === '5,9' && L4.find(l => l.row === 10).kind === 'total' && items(b4).length === 4);
ck('Extraction', 'numbered sections (1, 2) carry to their lines', find(b4, /Excavation in normal/).secs.join() === 'CIVIL WORKS' && find(b4, /LV switchgear/).secs.join() === 'ELECTRICAL WORKS');
ck('Extraction', 'the sum of the cost lines equals the grand total in this file', E.decStr(E.decSum(items(b4).map(l => E.dec(l.amount)))) === b4.control.amount);
const b5 = read('05_backup_in_summary.xlsx').book;
ck('Extraction', 'an amount linked to a backup sheet says which sheet and cell it comes from', /linked to sheet Salaries backup cell F5/.test(find(b5, /Site staff salaries/).flags.join()));
ck('Extraction', 'the summary sheet grand total is chosen as the control total when the backup has its own total', b5.control.sheet === 'Summary' && b5.control.amount === '1731000');
const b7 = read('07_combined.xlsx').book;
ck('Extraction', 'material and labour amount columns are kept as a breakdown beside the total amount', b7.sheets[1].header.cols.amount === 'G' && find({ sheets: [b7.sheets[1]] }, /Supply and install/).extra.map(e => e.name + '=' + e.amount).join() === 'Material amount=190000,Labour amount=60000');
const b10 = read('10_negative_rev1.xlsx').book;
ck('Extraction', 'a negative adjustment is kept with its sign and flagged', find(b10, /Discount/).amount === '-150000' && find(b10, /Discount/).flags.includes('Negative amount'));
const b11 = read('11_currencies.xlsx').book;
ck('Extraction', 'a currency column gives each line its currency', items(b11).map(l => l.cur).join() === 'EUR,USD,SAR');
const b13 = read('13_missing_formula_results.xlsx').book;
ck('Extraction', 'a formula saved without its calculated value: the amount is missing (never zero) and flagged', items(b13).every(l => l.amount === null && /Formula result missing/.test(l.flags.join())) && b13.sheets[0].lines.find(l => l.kind === 'total').amount === null);
const b16 = read('16_no_header.xlsx').book;
ck('Extraction', 'a sheet without a header row asks for a header mapping, with a preview', b16.sheets[0].status === 'Needs header mapping' && b16.sheets[0].preview.length > 2);
const wb16 = E.readBook(X, new Uint8Array(fs.readFileSync(path.join(FX, '16_no_header.xlsx')))).wb;
const m16 = E.extractBook(wb16, X, { Rates: { row: 1, code: 0, desc: 1, qty: 2, unit: 3, rate: 4, amount: 5 } });
ck('Extraction', 'with a header mapping given by a person, the sheet is read: two lines from row 3', items(m16).length === 2 && items(m16)[0].row === 3 && items(m16)[0].amount === '123000' && m16.sheets[0].header.manual === true, m16.sheets[0]);
ck('Extraction', 'every non-empty row is kept: rows that are not cost lines stay as sections, notes, subtotals or totals', b4.sheets[0].lines.length === 9);
ck('Extraction', 'the same file read twice gives the same fingerprint', E.fingerprintText(E.extractBook(E.readBook(X, new Uint8Array(fs.readFileSync(path.join(FX, '04_formula_subtotals.xlsx')))).wb, X).sheets.flatMap(s => s.lines)) === E.fingerprintText(L4));

// ---------------- normalization
const b6 = read('06_similar_specs.xlsx').book, c6 = items(b6);
ck('Normalization', '"630 sq.mm XLPE cable", "XLPE cable 630mm2" and "Power cable 630 sq mm" all read 630 mm²', c6.slice(0, 3).every(l => E.attrsOf(l.desc).mm2 === '630'));
ck('Normalization', '...but the 13.8 kV cable is not the same item as the 132 kV ones, and 300 mm² is not 630 mm²', E.attrsOf(c6[2].desc).kv === '13.8' && E.attrsOf(c6[0].desc).kv === '132' && E.attrsOf(c6[3].desc).mm2 === '300');
ck('Normalization', 'abbreviations, units and spelling: "S&I", "cu.m", "labor"', E.norm('S&I earthing') === 'supply and install earthing' && E.normUnit('cu.m') === 'm³' && E.normUnit('Nos') === 'No.' && E.norm('Labor crew') === 'labour crew');
ck('Normalization', 'currency notation: SR, US$, €', E.normCur('SR') === 'SAR' && E.normCur('US$') === 'USD' && E.normCur('€') === 'EUR');
ck('Normalization', 'the original description is never replaced', rebar.desc === 'Supply of rebar Grade 60' && cls(rebar).norm === 'supply of rebar grade 60');

// ---------------- classification
const c1 = cls(rebar), crew = cls(find(b1, /fixing crew/));
ck('Classification', '"Supply of rebar" → Civil Works → Reinforcement / Rebar, cost type Material, by an approved rule', c1.wbs === 'W-CIV-06' && c1.cost_type === 'Material' && c1.layer === 'rule' && c1.status === 'Auto-Classified', c1);
ck('Classification', '"Rebar fixing crew" → Civil manpower, cost type Manpower: the WBS destination is kept apart from the cost type', crew.wbs === 'W-CIV-08' && crew.cost_type === 'Manpower');
ck('Classification', '"Cable pulling technicians" → Electrical Manpower → Cable laying', cls(find(b2, /pulling technicians/)).wbs === 'W-ELP-01');
ck('Classification', '"Excavation for cable trench" → Civil Works → Excavation (cost type left for the reviewer)', (x => x.wbs === 'W-CIV-03' && x.status === 'Pending Review' && x.flags.includes('Cost type not set'))(cls(find(b1, /Excavation/))));
ck('Classification', '"Site villa rent" → accommodation (SM4), "Recruitment fees" → recruitment (SM5)', cls(find(b1, /villa/)).wbs === 'W-SM4' && cls(find(b1, /Recruitment/)).wbs === 'W-SM5');
const tr = cls(find(b1, /Transformer supply/));
ck('Controls', '"Transformer supply" (SAR 5.7 million) is proposed as Transformers but held for review as high value', tr.wbs === 'W-ELM-02' && tr.status === 'Pending Review' && /High value/.test(tr.flags.join()), tr);
ck('Controls', 'value thresholds are by currency: EUR 1.64 million is high value at the EUR limit', /High value: at or above 250,000.00 EUR/.test(cls(items(b11)[0]).flags.join()));
const comb = items(b7).map(l => cls(l));
ck('Controls', 'combined supply-and-install lines go to Split Required; no split is invented', comb.every(c => c.status === 'Split Required'));
const fin = cls({ kind: 'item', desc: 'Bank guarantee charges (performance bond)', amount: '5000', unit_n: 'LS', secs: [], flags: [] });
ck('Controls', 'financing, contingency and management reserve need a person whatever the score (mandatory review)', fin.wbs === 'W-FIN' && fin.status === 'Pending Review' && /Mandatory review/.test(fin.flags.join()) && cls({ kind: 'item', desc: 'Contingency 3%', amount: '100', secs: [], flags: [] }).status === 'Pending Review');
ck('Controls', 'a negative adjustment is held for review', cls(find(b10, /Discount/)).status === 'Pending Review');
ck('Controls', 'a line whose formula result is missing is held for review', items(b13).every(l => ['Pending Review', 'Unclassified'].includes(cls(l).status)) && cls(items(b13)[0]).status === 'Pending Review');
const unk = items(read('08_unknown.xlsx').book).map(l => cls(l));
ck('Classification', 'unknown descriptions stay Unclassified; no WBS is invented', unk.every(c => c.status === 'Unclassified' && (c.wbs === null || c.conf < 0.8)), unk.map(c => [c.status, c.wbs, c.conf]));
ck('Classification', 'section headings, subtotals and totals are not classified', cls(L4.find(l => l.kind === 'subtotal')).status === 'Not a cost line');

// approved WBS only
const W1 = W0.map(w => w.id === 'W-SM4' ? { ...w, cur: { ...w.cur, active: false } } : w);
ck('WBS master', 'an inactive element is never a destination: the villa line no longer goes to SM4', cls(find(b1, /villa/), { wbs: W1 }).wbs !== 'W-SM4');
const W2 = E.seedWbs();   // as delivered: proposals, nothing approved
ck('WBS master', 'until the company approves the master, nothing is classified (no destination exists)', items(b1).every(l => cls(l, { wbs: W2, rules: E.seedRules() }).status === 'Unclassified'));
const W3 = W0.map(w => w.id === 'W-CIV-06' ? { ...w, cur: { ...w.cur, eff_to: '2026-06-30' } } : w);
ck('WBS master', 'an element past its effective-to date is not used', cls(rebar, { wbs: W3 }).wbs !== 'W-CIV-06');
ck('WBS master', 'a parent (not postable) element is never a destination', items(b1).map(l => cls(l).wbs).every(w => !['W-SM', 'W-CIV', 'W-ELM'].includes(w)));

// approved mappings: scope, precedence, conflicts, expiry
const mp = (id, scope, key, wbs, ct, extra) => ({ id, ver: 1, status: 'Approved', cur: Object.assign({ scope, key, aliases: [], wbs_id: wbs, cost_type: ct, project_id: scope === 'project' ? 'P1' : null, ptype: scope === 'ptype' ? '132 kV substation' : null, active: true }, extra || {}) });
const zx = items(read('08_unknown.xlsx').book)[2];
ck('Mappings', 'an approved global mapping classifies a line no rule knows, at 100%, and names the mapping and its version', (c => c.wbs === 'W-CIV-10' && c.layer === 'map' && c.conf === 1 && c.refs.map === 'M-1' && c.status === 'Auto-Classified')(cls(zx, { maps: [mp('M-1', 'global', 'Zxq widget fee', 'W-CIV-10', 'Other')] })));
ck('Mappings', 'a project mapping wins over a project-type mapping, which wins over a global one', cls(zx, { maps: [mp('M-1', 'global', 'zxq widget fee', 'W-CIV-10', 'Other'), mp('M-2', 'ptype', 'zxq widget fee', 'W-SM3', 'Overhead'), mp('M-3', 'project', 'zxq widget fee', 'W-SM7', 'Overhead')] }).wbs === 'W-SM7');
ck('Mappings', "another project's mapping is not used", cls(zx, { pid: 'P2', maps: [mp('M-3', 'project', 'zxq widget fee', 'W-SM7', 'Overhead')] }).layer !== 'map');
const conf = cls(zx, { maps: [mp('M-1', 'global', 'zxq widget fee', 'W-CIV-10', 'Other'), mp('M-4', 'global', 'zxq widget fee', 'W-SM3', 'Overhead')] });
ck('Mappings', 'two approved mappings that disagree send the line to review, never pick one', conf.status === 'Pending Review' && /Conflicting approved mappings/.test(conf.flags.join()), conf);
ck('Mappings', 'an expired mapping is not used', cls(zx, { maps: [mp('M-1', 'global', 'zxq widget fee', 'W-CIV-10', 'Other', { eff_to: '2026-01-01' })] }).layer !== 'map');
ck('Mappings', 'an alias of an approved mapping matches too', cls(zx, { maps: [mp('M-5', 'global', 'something else', 'W-CIV-10', 'Other', { aliases: ['ZXQ widget fee'] })] }).refs.map === 'M-5');
ck('Mappings', 'a mapping to an element that is no longer approved is not used', cls(zx, { maps: [mp('M-1', 'global', 'zxq widget fee', 'W-SM4', 'Overhead')], wbs: W1 }).layer !== 'map');
// rules
const Rc = R0.concat([{ id: 'R-900', ver: 1, cur: { name: 'Villa as safety', wbs_id: 'W-SM6', cost_type: 'Overhead', priority: 10, strength: 0.96, all: [], any: ['villa'], none: [], active: true } }]);
const rc = cls(find(b1, /villa/), { rules: Rc });
ck('Rules', 'two rules of the same priority with different destinations: review, with both shown', rc.status === 'Pending Review' && /Conflicting approved rules/.test(rc.flags.join()) && rc.alt.length === 1, rc);
ck('Rules', 'a rule not yet approved is not used', cls(find(b1, /villa/), { rules: R0.map(r => r.cur.wbs_id === 'W-SM4' ? { ...r, cur: null, pend: { data: r.cur } } : r) }).layer !== 'rule');
// thresholds
ck('Thresholds', 'raising the automatic threshold above the rule strength sends rule results to confirmation (Proposed)', cls(rebar, { cfg: { ...E.SEED_CFG, auto: 0.98 } }).status === 'Proposed');
const sim = cls({ kind: 'item', desc: 'Pumping and dewatering of excavations', amount: '9000', secs: [], flags: [] }, { rules: [] });
ck('Thresholds', 'a similarity match is never auto-classified, however close', sim.layer === 'similar' && sim.status !== 'Auto-Classified', sim);
ck('Thresholds', 'below the review threshold a match is a hint only (Unclassified)', (c => c.status === 'Unclassified')(cls({ kind: 'item', desc: 'Excavation', amount: '1', secs: [], flags: [] }, { rules: [], cfg: { ...E.SEED_CFG, review: 0.999 } })));
// an outside provider (none is configured in the app; this is how its output would be checked)
const ctxP = p => ctxOf({ rules: [], provider: p });
const line8 = items(read('08_unknown.xlsx').book)[0];
const p1 = E.classify(line8, ctxP(() => 'not json'));
ck('AI provider', 'malformed provider output is rejected; the line stays, flagged, for a person', p1.layer !== 'ai' && /Invalid AI output: not an object/.test(p1.flags.join()) && p1.status !== 'Auto-Classified');
const p2 = E.classify(line8, ctxP(() => ({ wbs_id: 'W-NEW-99', confidence: 0.99 })));
ck('AI provider', 'a WBS the provider invents is rejected (it is not in the approved master)', /is not an approved, active element/.test(p2.flags.join()) && p2.wbs !== 'W-NEW-99');
const p3 = E.classify(line8, ctxP(() => { throw new Error('timeout'); }));
ck('AI provider', 'a provider failure does not lose the line: it stays for review with the reason', /AI service failed: timeout/.test(p3.flags.join()) && p3.status !== 'Auto-Classified');
const p4 = E.classify(line8, ctxP(() => ({ wbs_id: 'W-ELM-09', confidence: 0.99, amount: 1 })));
ck('AI provider', 'a provider that tries to give an amount is rejected', /never taken from it/.test(p4.flags.join()));
const p5 = E.classify(line8, ctxP(() => ({ wbs_id: 'W-ELM-09', cost_type: 'Material', confidence: 0.99, explanation: 'overhead line accessory' })));
ck('AI provider', 'a valid provider proposal at 99% still needs a person (never auto-classified on its own)', p5.layer === 'ai' && p5.wbs === 'W-ELM-09' && p5.status === 'Proposed', p5);
ck('AI provider', 'the amount of the line is never changed by classification', line8.amount === '31200');
// bulk approval eligibility
ck('Review', 'bulk approval takes a clean auto-classification', E.bulkEligible(c1) === null);
ck('Review', 'bulk approval never takes high-value, mandatory, conflicting or combined lines', [tr, fin, conf, comb[0]].every(c => E.bulkEligible(c)));

// ---------------- v3.37 stage 3: sheet roles, duplicates and backups, tolerances, splits, budget import
let lid = 0; const linesOf = f => { const bk = read(f).book; return { bk, L: bk.sheets.flatMap(s => s.lines.map(l => ({ ...l, sheet: s.sheet, id: 'L' + (++lid), file: f, file_id: f, cur: 'SAR' }))) }; };
const f5 = linesOf('05_backup_in_summary.xlsx'), f6 = linesOf('06_similar_specs.xlsx'), f7 = linesOf('07_combined.xlsx'), f3 = linesOf('03_hidden_merged.xlsx');
const roles = x => Object.fromEntries(E.proposeRoles(x.bk.name || 'f', x.bk.sheets.map(s => ({ sheet: s.sheet, hidden: s.hidden })), x.L, x.bk.control).map(r => [r.sheet, r.role]));
ck('Sheet roles', 'a sheet a summary line takes its amount from is a supporting backup; the sheet of the control total is the summary', (r => r.Summary === 'summary' && r['Salaries backup'] === 'backup')(roles(f5)), roles(f5));
ck('Sheet roles', 'a hidden calculation sheet next to a summary is proposed as a backup', roles(f3).Calc === 'backup', roles(f3));
ck('Sheet roles', 'the basis of each proposal is given', E.proposeRoles('05.xlsx', f5.bk.sheets.map(s => ({ sheet: s.sheet })), f5.L, f5.bk.control).every(r => r.basis && r.basis.length));
ck('Sheet roles', 'only summaries and detailed breakdowns count', JSON.stringify(E.COUNTING_ROLES) === '["summary","breakdown"]' && E.ROLES.length === 6);
const C = E.findDups([...f5.L, ...f6.L, ...f7.L], E.lexicon(E.SEED_CFG)), byK = k => C.filter(c => c.kind === k);
const d6 = f6.L.filter(l => l.kind === 'item'), s5 = f5.L.find(l => /Site staff salaries/.test(l.desc));
ck('Duplicates', 'two descriptions of the same cable with the same quantity, rate and amount are a "same figures" candidate, to be decided', byK('figures').some(c => c.lines.join() === [d6[0].id, d6[1].id].join() && c.blocking), byK('figures'));
ck('Duplicates', 'similar descriptions with a different size (630 against 300 mm2) are only shown as different specifications, not blocking', byK('spec').length >= 1 && byK('spec').every(c => !c.blocking && c.evidence[0].includes('mm2')), byK('spec'));
ck('Duplicates', 'the 13.8 kV cable is not a candidate of the 132 kV cable', !C.some(c => c.lines.includes(d6[2].id)));
const bk5 = byK('backup').find(c => c.lines[0] === s5.id);
ck('Backups', 'the summary line linked to the backup sheet is a backup candidate with its three backup lines adding up to it', bk5 && bk5.backup_lines.length === 3 && bk5.blocking && /add up to 1656000/.test(bk5.evidence[0]), bk5);
ck('Backups', 'a combined line equal to the total of a breakdown sheet is a backup candidate too', byK('backup').some(c => f7.L.find(l => l.id === c.lines[0] && /Supply and install cable/.test(l.desc)) && c.backup_lines.length === 1));
ck('Duplicates', 'candidate ids are stable: the same lines give the same id', JSON.stringify(E.findDups([...f6.L], E.lexicon(E.SEED_CFG)).map(c => c.id)) === JSON.stringify(C.filter(c => c.lines.every(i => d6.some(l => l.id === i))).map(c => c.id)));
const fig = byK('figures')[0];
ck('Decisions', 'duplicate: every line not kept stops counting', JSON.stringify(E.dupEffect(fig, 'duplicate', [fig.lines[0]]).targets) === JSON.stringify([fig.lines[1]]));
ck('Decisions', 'a valid independent cost keeps both lines counting', E.dupEffect(fig, 'valid', []).targets.length === 0);
ck('Decisions', 'duplicate with no line kept is refused', (() => { try { E.dupEffect(fig, 'duplicate', []); return false } catch (e) { return /keep|count/i.test(e.message) } })());
ck('Decisions', 'backup: the summary line counts and the backup lines do not', (x => x.targets.length === 3 && !x.targets.includes(s5.id) && x.includes.length === 0)(E.dupEffect(bk5, 'backup', null, false)));
ck('Decisions', 'backup counted in detail: the backup lines count (whatever their sheet\'s role) and the summary line does not', (x => JSON.stringify(x.targets) === JSON.stringify([s5.id]) && x.includes.length === 3)(E.dupEffect(bk5, 'backup', null, true)));
ck('Tolerance', 'the tolerance is the larger of the amount and the percentage, by currency and project type', E.decStr(E.tolOf({ tols: [{ cur: 'SAR', abs: '1', pct: '0.01' }] }, 'SAR', null, '1731000')) === '173.1' && E.decStr(E.tolOf({ tols: [{ cur: 'SAR', abs: '1', pct: '0.01' }] }, 'SAR', null, '500')) === '1'
  && E.decStr(E.tolOf({ tols: [{ cur: 'SAR', abs: '1', pct: '0.01' }, { cur: 'SAR', ptype: '132 kV substation', abs: '5', pct: '0' }] }, 'SAR', '132 kV substation', '1731000')) === '5');
const al = E.allocate('48000', [{ wbs_id: 'A', cost_type: 'Material', pct: '62.5' }, { wbs_id: 'B', cost_type: 'Manpower', pct: '37.5' }], 'SAR', true);
ck('Splits', 'a split by percentages gives exact amounts that add up to the line', al.ok && al.rows.map(r => r.amount).join() === '30000,18000', al);
const al3 = E.allocate('100', [{ wbs_id: 'A', pct: '33.33' }, { wbs_id: 'B', pct: '33.33' }, { wbs_id: 'C', pct: '33.34' }], 'SAR', true);
ck('Splits', 'rounding to the currency goes to the last row, never lost', al3.ok && al3.sum === '100', al3);
ck('Splits', 'amounts that do not add up to the line are shown with the difference', (x => !x.ok && x.diff === '1000')(E.allocate('48000', [{ wbs_id: 'A', amount: '30000' }, { wbs_id: 'B', amount: '17000' }], 'SAR', false)));
ck('Splits', 'percentages that do not make 100 are refused', (() => { try { const x = E.allocate('100', [{ wbs_id: 'A', pct: '50' }, { wbs_id: 'B', pct: '40' }], 'SAR', true); return !x.ok } catch (e) { return true } })());
const aoa = f => X.utils.sheet_to_json(E.readBook(X, new Uint8Array(fs.readFileSync(path.join(FX, f)))).wb.Sheets.Budget, { header: 1, raw: true, defval: null });
const pb = E.parseBudget(aoa('18_budget_import.xlsx'));
ck('Budget import', 'the header is found below a title row, with the SAP WBS ID, code, description, user field and cost type columns', pb.header_row === 3 && ['sap', 'code', 'desc', 'uf', 'ct'].every(k => pb.map[k] != null), pb.map);
ck('Budget import', 'the three amount columns are offered (Tender, Rev 0, Revised Rev 0)', pb.amountCols.map(c => c.name).join() === 'Tender,Rev 0,Revised Rev 0', pb.amountCols);
ck('Budget import', 'five element rows, with their actual SAP WBS IDs kept as written, and the total row recognised', pb.rows.filter(r => !r.total).map(r => r.sap).join() === 'PE-555-01-001-01,PE-555-01-001-02,PE-555-04-001,PE-555-05-001,PE-555-13' && pb.rows.filter(r => r.total).length === 1);
ck('Budget import', 'a sheet without a SAP WBS column is refused with the reason', /No header row/.test(E.parseBudget([['a', 'b'], [1, 2]]).error || ''));
const pi = E.parseBudget(aoa('19_budget_import_invalid.xlsx'));
ck('Budget import', 'a workbook with mistakes is still parsed row by row, so each refused row can be shown with its reason', pi.rows.length === 5 && pi.amountCols.map(c => c.name).join() === 'Rev 0' && pi.rows[2].raw[3] === 'TBC' && pi.rows[4].sap === null, pi.rows.map(r => r.sap));

// ---------------- v3.38 stage 4: SAP reports, the cost summary, the SAP loading workbook
const sheet0 = f => { const wb = E.readBook(X, new Uint8Array(fs.readFileSync(path.join(FX, f)))).wb; return X.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true, defval: null }); };
const P08 = E.parseSapReport(sheet0('20_sap_wbs_2026-08.xlsx')), C08 = E.sapCheck(P08, { period: '2026-08', cur: 'SAR' });
ck('SAP reports', 'a by-WBS report (S_ALR_87013558) is found below its title rows: Object, Budget, Actual, Commitment', P08.kind === 'wbs' && P08.header_row === 4 && ['wbs', 'budget', 'actual', 'commit'].every(k => P08.map[k] != null), P08.map);
ck('SAP reports', 'the WBS element and its description in one cell are split ("PE-555-04-001 Cables material")', P08.rows.some(r => r.wbs === 'PE-555-04-001' && r.desc === 'Cables material'));
ck('SAP reports', 'with totals at each level, an element counts only what is not in the elements below it: the totals are the leaves (8,370,000 / 4,735,000 / 2,700,000)', C08.ok && E.decStr(C08.tot.budget) === '8370000' && E.decStr(C08.tot.actual) === '4735000' && E.decStr(C08.tot.commit) === '2700000', C08.errs);
ck('SAP reports', '...and the total row is checked against them', C08.ftot && E.decStr(C08.ftot.budget) === '8370000');
ck('SAP reports', 'without that option every row counts as written (and the total row no longer matches)', !E.sapCheck(P08, { period: '2026-08', cur: 'SAR', hier: false }).ok);
const Pi = E.parseSapReport(sheet0('22_cji3_2026-09.xlsx')), Ci = E.sapCheck(Pi, { period: '2026-09', cur: 'SAR' });
ck('SAP reports', 'actual cost line items (CJI3): posting date, document, value; SAP dates 30.09.2026 and a trailing minus (1,500.00-) read', Pi.kind === 'actual' && Ci.ok && Ci.rows[0].date === '2026-09-30' && E.decStr(Ci.by.get('pe-555-04-001').actual) === '118500', Ci.errs);
ck('SAP reports', 'a posting outside the period is refused (or allowed before it with "to the end of the period")', !E.sapCheck(Pi, { period: '2026-10', cur: 'SAR' }).ok && E.sapCheck(Pi, { period: '2026-10', cur: 'SAR', cumulative: true }).ok && !E.sapCheck(Pi, { period: '2026-08', cur: 'SAR', cumulative: true }).ok);
const Pc = E.parseSapReport(sheet0('24_cji5_2026-09.xlsx'));
ck('SAP reports', 'commitment line items (CJI5, with a purchasing document) are recognised as commitments', Pc.kind === 'commit' && E.decStr(E.sapCheck(Pc, { period: '2026-09', cur: 'SAR' }).tot.commit) === '2470000');
const Cx = E.sapCheck(E.parseSapReport(sheet0('23_sap_invalid.xlsx')), { period: '2026-09', cur: 'SAR' });
ck('SAP reports', 'a report with mistakes is refused with each reason: not a number, another currency, no WBS element, repeated, the total row', !Cx.ok && ['is not a number', 'in USD', 'no WBS element', 'repeated in the report', 'the total row gives'].every(m => Cx.errs.some(e => e.includes(m))), Cx.errs);
ck('SAP reports', 'a template finds its columns by their headings; a missing one is said', E.parseSapReport(sheet0('20_sap_wbs_2026-08.xlsx'), { name: 'T', kind: 'wbs', map: { wbs: 'Object', actual: 'Actual' } }).map.actual === 2
   && /were not found/.test(E.parseSapReport(sheet0('20_sap_wbs_2026-08.xlsx'), { name: 'T', kind: 'wbs', map: { wbs: 'WBS Element' } }).error || ''));
const rep = (id, period, f, o) => { const P = E.parseSapReport(sheet0(f)), c = E.sapCheck(P, Object.assign({ period, cur: 'SAR' }, o || {})); return { id, period, kind: c.kind, cumulative: !!(o || {}).cumulative, has: c.has, by: c.by }; };
const REP = [rep('R7', '2026-07', '21_sap_wbs_2026-07.xlsx'), rep('R8', '2026-08', '20_sap_wbs_2026-08.xlsx'), rep('R9', '2026-09', '22_cji3_2026-09.xlsx'), rep('C9', '2026-09', '24_cji5_2026-09.xlsx')];
const F8 = E.sapFigures(REP, '2026-08'), F9 = E.sapFigures(REP, '2026-09'), g = (F, k, f) => E.decStr(F.fig.get(k)[f]);
ck('Figures', 'August: the actual of the month is the difference of the July and August reports (600,000 - 480,000)', g(F8, 'pe-555-01-001-01', 'actual') === '600000' && g(F8, 'pe-555-01-001-01', 'actual_p') === '120000' && /difference/.test(F8.basis.actual_p));
ck('Figures', 'September: actual to date = the August report + the September line items; commitments from CJI5 (a snapshot)', g(F9, 'pe-555-04-001', 'actual') === '3118500' && g(F9, 'pe-555-04-001', 'actual_p') === '118500' && g(F9, 'pe-555-04-001', 'commit') === '2380000' && F9.basis.commit.includes('commitment'));
ck('Figures', '...the SAP budget from the latest by-WBS report up to the period', g(F9, 'pe-555-05-001', 'sap_budget') === '900000' && F9.basis.sap_budget.includes('2026-08'));
ck('Figures', 'a missing month is said, never filled in', E.sapFigures([REP[0], REP[2]], '2026-09').notes.some(n => /2026-08/.test(n)));
const pb18 = E.parseBudget(aoa('18_budget_import.xlsx')), col = n => pb18.amountCols.find(c => c.name === n).c;
const vl = n => pb18.rows.filter(r => !r.total).map((r, i) => ({ n: i + 1, sap_wbs_id: r.sap, wbs_code: r.code, descr: r.desc, user_field: r.uf, amount: E.decStr(E.dec(r.raw[col(n)])) }));
const VERS = [{ id: 'T', kind: 'Tender estimate', rev_no: 0, status: 'Approved in ProTrackAI', approved_at: '2026-06-01', lines: vl('Tender') }, { id: 'V0', kind: 'Rev 0', rev_no: 0, status: 'SAP Loading Confirmed', approved_at: '2026-07-01', lines: vl('Rev 0') },
  { id: 'V1', kind: 'Revised Rev 0', rev_no: 0, status: 'Submitted', submitted_at: '2026-09-01', lines: vl('Revised Rev 0') }];
const CS = E.costSummary({ pcode: 'PE-555', sep: '-', versions: VERS, fig: F9, names: { 'pe-555-04': 'Electrical Material' } }), row = k => CS.rows.find(r => r.key === k).c, s = x => x == null ? null : E.decStr(x);
ck('Cost summary', 'the 24 columns, each with its definition', E.CS_COLS.length === 24 && E.CS_COLS.slice(5).every(([k]) => E.CS_DEF[k]));
ck('Cost summary', 'tender, Rev 0 and current budget; the revision waiting for approval as a change (-150,000 on the cables)', s(row('pe-555-04-001').tender) === '5000000' && s(row('pe-555-04-001').rev0) === '5100000' && s(row('pe-555-04-001').current) === '5100000' && s(row('pe-555-04-001').pending) === '-150000');
ck('Cost summary', 'over budget: actual 3,118,500 + commitments 2,380,000 > 5,100,000 → EAC 5,498,500, VAC -398,500', s(row('pe-555-04-001').eac) === '5498500' && s(row('pe-555-04-001').vac) === '-398500' && row('pe-555-04-001').status.includes('Over budget'));
ck('Cost summary', 'at risk at 90% committed, and the SAP budget (900,000) differing from the approved 910,000', row('pe-555-05-001').status.includes('At risk') && row('pe-555-05-001').status.includes('SAP budget differs') && s(row('pe-555-05-001').bud_diff) === '10000');
ck('Cost summary', 'an element with cost in SAP but not in the approved budget is shown so', row('pe-555-09-001').status.includes('Not in the approved budget') && s(row('pe-555-09-001').actual) === '15000');
ck('Cost summary', 'the levels above add up their elements, named from the master', s(row('pe-555-04').actual) === '3118500' && CS.rows.find(r => r.key === 'pe-555-04').desc === 'Electrical Material' && CS.rows.find(r => r.key === 'pe-555-04').kids);
ck('Cost summary', 'the total of the project counts each element once, and its EAC is the sum of the elements (an overrun is not hidden)', s(CS.total.current) === '8380000' && s(CS.total.actual) === '4968500' && s(CS.total.eac) === '8793500' && s(CS.total.vac) === '-413500', [s(CS.total.current), s(CS.total.actual), s(CS.total.eac)]);
ck('Cost summary', 'percentages: % spent and % committed of the current budget', Number(row('pe-555-01-001-01').pct_spent).toFixed(1) === '54.0');
ck('Cost summary', 'without a SAP report, only the budget columns: nothing is estimated', (r => r.actual === null && r.commit === null && r.status.length === 0)(E.costSummary({ pcode: 'PE-555', versions: VERS }).rows.find(r => r.key === 'pe-555-04-001').c));
const SC0 = E.sapContent(vl('Rev 0'), null, 'PE-555', { sep: '-', digits: [2, 3, 2] }), SC1 = E.sapContent(vl('Revised Rev 0'), vl('Rev 0'), 'PE-555', { sep: '-', digits: [2, 3, 2] });
ck('SAP loading', 'the first loading: the amounts by SAP WBS ID, every ID valid for the project', SC0.items.length === 5 && SC0.changes === null && SC0.excluded.length === 0 && SC0.total === '8380000');
ck('SAP loading', 'a revision: supplements and returns against the version loaded', JSON.stringify(SC1.changes.map(x => [x.sap, x.diff])) === JSON.stringify([['PE-555-01-001-01', '50000'], ['PE-555-01-001-02', '20000'], ['PE-555-04-001', '-150000'], ['PE-555-05-001', '-4999.5']]));
ck('SAP loading', 'an ID of another project, or with wrong digits, is excluded with the reason', (x => x.excluded.map(e => e.reason).join('|') === "does not start with the project's PE number PE-555|level 1 should be 2 digits (\"1\")")(E.sapContent([{ n: 1, sap_wbs_id: 'PE-999-01', amount: '1' }, { n: 2, sap_wbs_id: 'PE-555-1', amount: '1' }], null, 'PE-555', { sep: '-', digits: [2, 3, 2] })));
const WB = E.sapWorkbook({ content: { ...SC1, prev: { kind: 'Rev 0', rev_no: 0, sap_ref: 'CJ30-4711' } }, project: { code: 'PE-555', name: 'Old Line' }, version: { id: 'V1', kind: 'Revised Rev 0', rev_no: 0, currency: 'SAR', status: 'Ready for SAP Loading' }, prev: { kind: 'Rev 0', rev_no: 0, sap_ref: 'CJ30-4711' }, gen: { by: 'C', at: '2026-10-23T10:00', seq: 1, check: 'x' }, hist: [] });
ck('SAP loading', 'the workbook has its six sheets', WB.sheets.map(x => x.name).join('|') === 'Header|WBS Elements|Original Budget|Supplements & Returns|Control Totals|Approvals & Checks');
ck('SAP loading', 'a revision fills Supplements & Returns (4 rows) and says Original Budget is not used', WB.sheets[3].aoa.length === 5 && WB.sheets[3].aoa[3][5] === 'Return' && /Not used/.test(WB.sheets[2].aoa[0][0]));
ck('SAP loading', 'the control totals add up: previously loaded + supplements + returns = the total', WB.ok && WB.sheets[4].aoa.some(r => r[2] === 'OK'));
ck('SAP loading', 'the WBS Elements sheet adds the levels above with their parents', WB.sheets[1].aoa.some(r => r[0] === 'PE-555-01-001' && r[2] === 'PE-555-01' && r[1] === 2));
ck('SAP loading', 'the header says nothing was sent to SAP', WB.sheets[0].aoa.some(r => /Nothing has been sent to SAP/.test(r[0] || '')));

const passed = R.filter(r => r.result === 'PASS').length;
console.log(JSON.stringify({ suite: 'bcm_engine', engine: E.ENGINE, passed, total: R.length, checks: R }, null, 1));
process.exitCode = passed === R.length ? 0 : 1;
