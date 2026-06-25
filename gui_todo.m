#import <Cocoa/Cocoa.h>

#pragma mark - Palette / helpers

static NSColor *PaletteColor(NSInteger i) {
    static NSArray *p = nil;
    if (!p) p = @[ NSColor.systemRedColor, NSColor.systemOrangeColor,
                   NSColor.systemYellowColor, NSColor.systemGreenColor,
                   NSColor.systemBlueColor, NSColor.systemPurpleColor,
                   NSColor.systemPinkColor, NSColor.systemTealColor ];
    NSInteger n = (NSInteger)p.count;
    return p[((i % n) + n) % n];
}

static NSColor *PriorityColor(NSInteger level) {
    switch (level) {
        case 1: return NSColor.systemBlueColor;
        case 2: return NSColor.systemOrangeColor;
        case 3: return NSColor.systemRedColor;
        default: return NSColor.clearColor;
    }
}

#pragma mark - Models

@interface Category : NSObject
@property (copy) NSString *name;
@property NSInteger colorIndex;
@end
@implementation Category
- (id)copyWithZone:(NSZone *)z {
    Category *c = [[Category allocWithZone:z] init];
    c.name = self.name; c.colorIndex = self.colorIndex;
    return c;
}
@end

@interface Task : NSObject
@property BOOL done;
@property (copy) NSString *text;
@property NSInteger priority;     /* 0 none, 1 low, 2 med, 3 high */
@property (copy) NSString *category;
@property (strong) NSDate *due;   /* nil = none, normalized to local midnight */
@property (copy) NSString *createdISO;
@end
@implementation Task
- (id)copyWithZone:(NSZone *)z {
    Task *t = [[Task allocWithZone:z] init];
    t.done = self.done; t.text = self.text; t.priority = self.priority;
    t.category = self.category; t.due = self.due; t.createdISO = self.createdISO;
    return t;
}
@end

typedef NS_ENUM(NSInteger, SmartKind) {
    SmartAll = 0, SmartActive, SmartCompleted, SmartFlagged
};
typedef NS_ENUM(NSInteger, FilterMode) {
    FilterAll = 0, FilterActive, FilterDone
};
typedef NS_ENUM(NSInteger, RowKind) {
    RowHeader = 0, RowSmart, RowSeparator, RowCategory
};

@interface SidebarRow : NSObject
@property RowKind kind;
@property (copy) NSString *title;
@property SmartKind smart;
@property (strong) Category *category;
@property (copy) NSString *glyph;
@end
@implementation SidebarRow @end

#pragma mark - Small drawn views

@interface CheckboxView : NSView
@property BOOL on;
@property NSInteger priority;
@property (copy) void (^onToggle)(void);
@end
@implementation CheckboxView
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return NO; }
- (void)viewDidChangeEffectiveAppearance { [self setNeedsDisplay:YES]; }
- (void)mouseDown:(NSEvent *)e { /* consume; toggle on mouseUp inside bounds */ }
- (void)mouseUp:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (NSMouseInRect(p, self.bounds, self.isFlipped) && self.onToggle) self.onToggle();
}
- (void)drawRect:(NSRect)dirty {
    CGFloat d = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) - 3;
    NSRect r = NSMakeRect((NSWidth(self.bounds) - d) / 2,
                          (NSHeight(self.bounds) - d) / 2, d, d);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:r];
    if (self.on) {
        [NSColor.controlAccentColor setFill];
        [circle fill];
        NSBezierPath *check = [NSBezierPath bezierPath];
        [check moveToPoint:NSMakePoint(NSMinX(r) + d * 0.26, NSMinY(r) + d * 0.52)];
        [check lineToPoint:NSMakePoint(NSMinX(r) + d * 0.43, NSMinY(r) + d * 0.34)];
        [check lineToPoint:NSMakePoint(NSMinX(r) + d * 0.74, NSMinY(r) + d * 0.68)];
        check.lineWidth = MAX(1.5, d * 0.12);
        check.lineCapStyle = NSLineCapStyleRound;
        check.lineJoinStyle = NSLineJoinStyleRound;
        [[NSColor whiteColor] setStroke];
        [check stroke];
    } else {
        NSColor *c = self.priority > 0 ? PriorityColor(self.priority)
                                       : NSColor.tertiaryLabelColor;
        [c setStroke];
        circle.lineWidth = 1.5;
        [circle stroke];
    }
}
@end

@interface BarView : NSView
@property NSInteger level;
@end
@implementation BarView
- (void)viewDidChangeEffectiveAppearance { [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirty {
    if (self.level <= 0) return;
    [PriorityColor(self.level) setFill];
    NSRectFill(self.bounds);
}
@end

#pragma mark - Cell views

@interface TaskCellView : NSTableCellView
@property (strong) BarView *bar;
@property (strong) CheckboxView *check;
@property (strong) NSTextField *titleField;
@property (strong) NSTextField *dueField;
@property (strong) NSTextField *tagField;
@end
@implementation TaskCellView @end

@interface SidebarCellView : NSTableCellView
@property (strong) NSTextField *lead;
@property (strong) NSTextField *titleField;
@property (strong) NSTextField *badge;
@end
@implementation SidebarCellView @end

#pragma mark - Table subclasses (keyboard)

@protocol KeyTableDelegate <NSObject>
- (BOOL)keyTable:(NSTableView *)t handleKey:(NSEvent *)e;
@end

@interface KeyTable : NSTableView
@property (weak) id<KeyTableDelegate> keyHandler;
@end
@implementation KeyTable
- (void)keyDown:(NSEvent *)e {
    /* let the controller intercept; it returns YES if it consumed the key */
    if (self.keyHandler && [self.keyHandler keyTable:self handleKey:e]) return;
    [super keyDown:e];
}
@end

#pragma mark - Controller

@interface AppController : NSObject <NSApplicationDelegate, NSTableViewDataSource,
                                     NSTableViewDelegate, NSTextFieldDelegate,
                                     NSSearchFieldDelegate, NSSplitViewDelegate,
                                     KeyTableDelegate>
@property (strong) NSWindow *window;
@property (strong) NSSplitView *split;
@property (strong) KeyTable *sidebar;
@property (strong) KeyTable *mainTable;
@property (strong) NSTextField *headerLabel;
@property (strong) NSSearchField *search;
@property (strong) NSSegmentedControl *filterSeg;
@property (strong) NSTextField *input;
@property (strong) NSPopUpButton *prioPop;
@property (strong) NSTextField *status;
@property (strong) NSTextField *placeholder;

@property (strong) NSMutableArray<Task *> *allTasks;
@property (strong) NSMutableArray<Category *> *categories;
@property (strong) NSMutableArray<SidebarRow *> *rows;
@property (strong) NSMutableArray<Task *> *visible;

@property SmartKind selectedSmart;
@property (strong) Category *selectedCategory;   /* nil => smart list */
@property FilterMode filterMode;
@property (copy) NSString *searchString;

@property (weak) Task *editingTask;
@property (strong) NSUndoManager *undo;
@property (copy) NSString *dbPath;
@end

@implementation AppController

#pragma mark Persistence path

- (NSString *)resolveDBPath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: NSHomeDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"gui_todo"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"tasks.txt"];
}

#pragma mark Escaping

static NSString *Escape(NSString *s) {
    NSMutableString *m = [s mutableCopy];
    [m replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\t" withString:@"\\t" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, m.length)];
    [m replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, m.length)];
    return m;
}
static NSString *Unescape(NSString *s) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' && i + 1 < n) {
            unichar d = [s characterAtIndex:++i];
            if (d == 't') [out appendString:@"\t"];
            else if (d == 'n') [out appendString:@"\n"];
            else if (d == 'r') [out appendString:@"\r"];
            else if (d == '\\') [out appendString:@"\\"];
            else { [out appendFormat:@"%C", d]; }
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

#pragma mark Date formatters

- (NSDateFormatter *)isoFormatter {
    static NSDateFormatter *f = nil;
    if (!f) {
        f = [NSDateFormatter new];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    }
    return f;
}
- (NSDateFormatter *)dayFormatter {
    static NSDateFormatter *f = nil;
    if (!f) {
        f = [NSDateFormatter new];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd";
    }
    return f;
}
- (NSString *)nowISO { return [[self isoFormatter] stringFromDate:[NSDate date]]; }

#pragma mark Categories

- (Category *)categoryNamed:(NSString *)name {
    for (Category *c in self.categories)
        if ([c.name caseInsensitiveCompare:name] == NSOrderedSame) return c;
    return nil;
}
- (NSInteger)lowestUnusedColorIndex {
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (Category *c in self.categories)
        if (c.colorIndex >= 0 && c.colorIndex < 8) [used addIndex:c.colorIndex];
    for (NSInteger i = 0; i < 8; i++) if (![used containsIndex:i]) return i;
    return (NSInteger)self.categories.count % 8;
}
- (Category *)ensureCategory:(NSString *)name {
    Category *c = [self categoryNamed:name];
    if (c) return c;
    c = [Category new];
    c.name = name;
    c.colorIndex = [self lowestUnusedColorIndex];
    [self.categories addObject:c];
    return c;
}
- (void)ensureInbox {
    if (!self.categories) self.categories = [NSMutableArray array];
    if (![self categoryNamed:@"Inbox"]) {
        Category *inbox = [Category new];
        inbox.name = @"Inbox"; inbox.colorIndex = 7;
        [self.categories insertObject:inbox atIndex:0];
    }
}

#pragma mark Load / Save

- (void)load {
    self.allTasks = [NSMutableArray array];
    self.categories = [NSMutableArray array];

    NSString *contents = [NSString stringWithContentsOfFile:self.dbPath
                                                   encoding:NSUTF8StringEncoding error:nil];
    BOOL fromLegacyImport = NO;
    if (!contents) {
        /* one-time import of an old cwd-relative tasks.txt, if present */
        NSString *legacy = [NSString stringWithContentsOfFile:@"tasks.txt"
                                                     encoding:NSUTF8StringEncoding error:nil];
        if (legacy) { contents = legacy; fromLegacyImport = YES; }
    }

    if (!contents) {
        [self ensureInbox];
        [self ensureCategory:@"Work"];
        [self ensureCategory:@"Home"];
        return;
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];
    NSString *firstNonEmpty = nil;
    for (NSString *l in lines) {
        NSString *t = [l stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
        if (t.length) { firstNonEmpty = t; break; }
    }

    if ([firstNonEmpty isEqualToString:@"#todo v2"]) {
        for (NSString *line in lines) {
            if (line.length == 0) continue;
            NSArray *f = [line componentsSeparatedByString:@"\t"];
            NSString *type = f.firstObject;
            if ([type isEqualToString:@"C"] && f.count >= 3) {
                Category *c = [Category new];
                c.name = Unescape(f[1]);
                c.colorIndex = [f[2] integerValue];
                if (![self categoryNamed:c.name]) [self.categories addObject:c];
            } else if ([type isEqualToString:@"T"] && f.count >= 7) {
                Task *t = [Task new];
                t.done = [f[1] integerValue] != 0;
                t.priority = MIN(3, MAX(0, [f[2] integerValue]));
                t.category = Unescape(f[3]);
                NSString *dueStr = f[4];
                t.due = dueStr.length ? [[self dayFormatter] dateFromString:dueStr] : nil;
                if (t.due) t.due = [[NSCalendar currentCalendar] startOfDayForDate:t.due];
                t.createdISO = [f[5] length] ? f[5] : [self nowISO];
                /* text may itself have contained tabs -> rejoin remainder */
                NSString *text = [[f subarrayWithRange:NSMakeRange(6, f.count - 6)]
                                  componentsJoinedByString:@"\t"];
                t.text = Unescape(text);
                if (t.text.length) [self.allTasks addObject:t];
            }
        }
    } else {
        /* legacy v1:  "<0|1>\t<text>" per line */
        for (NSString *line in lines) {
            NSString *l = [line stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
            if (l.length < 2) continue;
            /* don't mis-parse a stray v2 record (or header) as a v1 line */
            if ([l hasPrefix:@"#"] || [l hasPrefix:@"C\t"] || [l hasPrefix:@"T\t"]) continue;
            Task *t = [Task new];
            t.done = [l characterAtIndex:0] == '1';
            NSRange tab = [l rangeOfString:@"\t"];
            NSString *text = (tab.location != NSNotFound)
                ? [l substringFromIndex:tab.location + 1] : [l substringFromIndex:1];
            t.text = [text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
            t.priority = 0; t.due = nil; t.category = @"Inbox";
            t.createdISO = [self nowISO];
            if (t.text.length) [self.allTasks addObject:t];
        }
    }

    [self ensureInbox];
    /* auto-create any category referenced by a task but missing from the roster */
    for (Task *t in self.allTasks) {
        if (!t.category.length) t.category = @"Inbox";
        t.category = [self ensureCategory:t.category].name;   /* canonical casing */
    }
    if (self.categories.count <= 1) { [self ensureCategory:@"Work"]; [self ensureCategory:@"Home"]; }

    if (fromLegacyImport) {
        /* keep a recoverable copy of the original before our first v2 write */
        NSString *bak = [[self.dbPath stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"tasks.txt.import.bak"];
        [contents writeToFile:bak atomically:YES
                     encoding:NSUTF8StringEncoding error:nil];
    }
}

- (void)save {
    NSMutableString *out = [NSMutableString stringWithString:@"#todo v2\n"];
    for (Category *c in self.categories)
        [out appendFormat:@"C\t%@\t%ld\n", Escape(c.name), (long)c.colorIndex];
    for (Task *t in self.allTasks) {
        NSString *due = t.due ? [[self dayFormatter] stringFromDate:t.due] : @"";
        [out appendFormat:@"T\t%d\t%ld\t%@\t%@\t%@\t%@\n",
            t.done ? 1 : 0, (long)t.priority, Escape(t.category ?: @"Inbox"),
            due, t.createdISO ?: [self nowISO], Escape(t.text ?: @"")];
    }
    NSError *err = nil;
    BOOL ok = [out writeToFile:self.dbPath atomically:YES
                      encoding:NSUTF8StringEncoding error:&err];
    if (!ok) self.status.stringValue =
        [NSString stringWithFormat:@"⚠︎ save failed: %@", err.localizedDescription];
}

#pragma mark Sidebar rows

- (SidebarRow *)row:(RowKind)k title:(NSString *)t { SidebarRow *r = [SidebarRow new]; r.kind = k; r.title = t; return r; }

- (void)rebuildRows {
    NSMutableArray *r = [NSMutableArray array];
    [r addObject:[self row:RowHeader title:@"Lists"]];
    NSArray *smartTitles = @[@"All", @"Active", @"Completed", @"Flagged"];
    NSArray *smartGlyphs = @[@"✦", @"○", @"✓", @"⚑"];
    for (NSInteger i = 0; i < 4; i++) {
        SidebarRow *s = [self row:RowSmart title:smartTitles[i]];
        s.smart = (SmartKind)i; s.glyph = smartGlyphs[i];
        [r addObject:s];
    }
    [r addObject:[self row:RowSeparator title:@""]];
    [r addObject:[self row:RowHeader title:@"Categories"]];
    for (Category *c in self.categories) {
        SidebarRow *s = [self row:RowCategory title:c.name];
        s.category = c;
        [r addObject:s];
    }
    self.rows = r;
}

- (NSInteger)countForSidebarRow:(SidebarRow *)row {
    NSInteger n = 0;
    for (Task *t in self.allTasks) {
        if (row.kind == RowSmart) {
            switch (row.smart) {
                case SmartAll: if (!t.done) n++; break;
                case SmartActive: if (!t.done) n++; break;
                case SmartCompleted: if (t.done) n++; break;
                case SmartFlagged: if (!t.done && t.priority >= 3) n++; break;
            }
        } else if (row.kind == RowCategory) {
            if (!t.done && [t.category isEqualToString:row.category.name]) n++;
        }
    }
    return n;
}

#pragma mark Filter pipeline

- (BOOL)passesScope:(Task *)t {
    if (self.selectedCategory)
        return [t.category isEqualToString:self.selectedCategory.name];
    switch (self.selectedSmart) {
        case SmartAll: return YES;
        case SmartActive: return !t.done;
        case SmartCompleted: return t.done;
        case SmartFlagged: return !t.done && t.priority >= 3;
    }
    return YES;
}
- (BOOL)passesMode:(Task *)t {
    switch (self.filterMode) {
        case FilterActive: return !t.done;
        case FilterDone: return t.done;
        default: return YES;
    }
}
- (BOOL)passesSearch:(Task *)t {
    if (!self.searchString.length) return YES;
    NSStringCompareOptions o = NSCaseInsensitiveSearch;
    return [t.text rangeOfString:self.searchString options:o].location != NSNotFound
        || [t.category rangeOfString:self.searchString options:o].location != NSNotFound;
}
- (void)recompute {
    NSMutableArray *v = [NSMutableArray array];
    for (Task *t in self.allTasks)
        if ([self passesScope:t] && [self passesMode:t] && [self passesSearch:t])
            [v addObject:t];
    self.visible = v;   /* manual order = allTasks order */
}

#pragma mark Refresh

- (Task *)selectedTask {
    NSInteger r = self.mainTable.selectedRow;
    return (r >= 0 && r < (NSInteger)self.visible.count) ? self.visible[r] : nil;
}

- (void)refreshView {
    Task *sel = [self selectedTask];
    [self recompute];
    [self rebuildRows];
    [self.sidebar reloadData];
    [self.mainTable reloadData];
    /* restore selection by identity */
    NSInteger idx = sel ? (NSInteger)[self.visible indexOfObjectIdenticalTo:sel] : NSNotFound;
    if (idx != NSNotFound)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    else if (self.visible.count)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateChrome];
}
- (void)refreshAll {        /* refreshView + persist (for model mutations) */
    [self refreshView];
    [self save];
}
- (void)refreshLight {
    /* model unchanged structurally; just redraw + counts + status */
    [self.mainTable reloadData];
    [self.sidebar reloadData];
    [self updateChrome];
}

- (void)updateChrome {
    NSString *name = self.selectedCategory ? self.selectedCategory.name
        : @[@"All", @"Active", @"Completed", @"Flagged"][self.selectedSmart];
    self.headerLabel.stringValue = name;

    NSInteger total = (NSInteger)self.visible.count, done = 0;
    for (Task *t in self.visible) if (t.done) done++;
    self.status.stringValue = total
        ? [NSString stringWithFormat:@"%ld of %ld done", (long)done, (long)total]
        : @"No tasks";

    BOOL empty = self.visible.count == 0;
    self.placeholder.hidden = !empty;
    if (empty)
        self.placeholder.stringValue = self.searchString.length
            ? @"No matches"
            : @"Nothing here yet.\nTry:  Buy milk @Home !! tomorrow";
}

#pragma mark Quick-add parsing

- (NSDate *)parseDueToken:(NSString *)tok {
    NSString *t = tok.lowercaseString;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    if ([t isEqualToString:@"today"] || [t isEqualToString:@"tod"]) return today;
    if ([t isEqualToString:@"tomorrow"] || [t isEqualToString:@"tmr"] || [t isEqualToString:@"tom"])
        return [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];

    NSArray *full = @[@"sunday",@"monday",@"tuesday",@"wednesday",@"thursday",@"friday",@"saturday"];
    NSArray *abbr = @[@"sun",@"mon",@"tue",@"wed",@"thu",@"fri",@"sat"];
    NSInteger target = -1;
    for (NSInteger i = 0; i < 7; i++)
        if ([t isEqualToString:full[i]] || [t isEqualToString:abbr[i]]) { target = i + 1; break; }
    if (target > 0) {
        NSInteger cur = [cal component:NSCalendarUnitWeekday fromDate:today];
        NSInteger delta = (target - cur + 7) % 7;   /* 0..6, today allowed */
        return [cal dateByAddingUnit:NSCalendarUnitDay value:delta toDate:today options:0];
    }
    NSDate *iso = [[self dayFormatter] dateFromString:t];
    if (iso) return [cal startOfDayForDate:iso];
    return nil;
}

- (void)parseQuickAdd:(NSString *)raw
                 text:(NSString **)outText
             priority:(NSInteger *)outPrio
             category:(NSString **)outCat
                  due:(NSDate **)outDue {
    *outPrio = -1; *outCat = nil; *outDue = nil;
    NSMutableArray *keep = [NSMutableArray array];
    NSArray *toks = [raw componentsSeparatedByCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]];
    for (NSString *tok in toks) {
        if (!tok.length) continue;
        if ([tok hasPrefix:@"@"] && tok.length > 1) {
            *outCat = [tok substringFromIndex:1];
        } else if ([tok rangeOfCharacterFromSet:
                    [[NSCharacterSet characterSetWithCharactersInString:@"!"] invertedSet]].location == NSNotFound
                   && tok.length <= 3) {
            *outPrio = (NSInteger)tok.length;   /* "!"=1 "!!"=2 "!!!"=3 */
        } else {
            NSDate *d = [self parseDueToken:tok];
            if (d && !*outDue) *outDue = d;
            else [keep addObject:tok];
        }
    }
    *outText = [[keep componentsJoinedByString:@" "]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark Mutations (snapshot-based undo)

- (NSMutableArray *)deepCopy:(NSArray *)a {
    NSMutableArray *m = [NSMutableArray arrayWithCapacity:a.count];
    for (id o in a) [m addObject:[o copy]];
    return m;
}
- (void)beginMutation:(NSString *)action {
    NSArray *pt = [self deepCopy:self.allTasks];
    NSArray *pc = [self deepCopy:self.categories];
    [[self.undo prepareWithInvocationTarget:self]
        restoreTasks:pt categories:pc action:action];
    [self.undo setActionName:action];
}
- (void)restoreTasks:(NSArray *)tasks categories:(NSArray *)cats action:(NSString *)action {
    NSInteger selRow = self.mainTable.selectedRow;   /* identity can't survive deep copy */
    NSArray *ct = [self deepCopy:self.allTasks];
    NSArray *cc = [self deepCopy:self.categories];
    [[self.undo prepareWithInvocationTarget:self]
        restoreTasks:ct categories:cc action:action];
    [self.undo setActionName:action];
    self.allTasks = [tasks mutableCopy];
    self.categories = [cats mutableCopy];
    [self ensureInbox];
    /* the selected category object may have been replaced by a copy */
    if (self.selectedCategory) {
        Category *again = [self categoryNamed:self.selectedCategory.name];
        if (again) self.selectedCategory = again; else { self.selectedCategory = nil; self.selectedSmart = SmartAll; }
    }
    [self refreshAll];
    /* restore selection by row position (identity was destroyed by the deep copy) */
    if (self.visible.count && selRow >= 0) {
        NSInteger r = MIN(selRow, (NSInteger)self.visible.count - 1);
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
    }
}

- (NSInteger)defaultPriorityFromPopup {
    return self.prioPop.indexOfSelectedItem;   /* 0 none .. 3 high */
}

- (void)addFromInput {
    NSString *raw = [self.input.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!raw.length) { NSBeep(); return; }
    NSString *text, *cat; NSInteger prio; NSDate *due;
    [self parseQuickAdd:raw text:&text priority:&prio category:&cat due:&due];
    if (!text.length) { NSBeep(); return; }

    [self beginMutation:@"Add Task"];
    Task *t = [Task new];
    t.text = text;
    t.done = NO;
    t.priority = prio >= 0 ? prio : [self defaultPriorityFromPopup];
    t.due = due;
    t.createdISO = [self nowISO];
    if (cat.length) t.category = [self ensureCategory:cat].name;   /* canonical casing */
    else if (self.selectedCategory) t.category = self.selectedCategory.name;
    else t.category = @"Inbox";
    [self.allTasks addObject:t];

    self.input.stringValue = @"";
    [self.prioPop selectItemAtIndex:0];
    [self recompute];
    [self rebuildRows];
    [self.sidebar reloadData];
    [self.mainTable reloadData];
    NSInteger idx = (NSInteger)[self.visible indexOfObjectIdenticalTo:t];
    if (idx != NSNotFound)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    [self updateChrome];
    [self save];
    [self.window makeFirstResponder:self.input];
}

- (void)toggleTask:(Task *)t {
    if (!t) return;
    [self beginMutation:@"Toggle Done"];
    t.done = !t.done;
    [self refreshAll];
}
- (void)deleteTask:(Task *)t {
    if (!t) return;
    NSInteger row = (NSInteger)[self.visible indexOfObjectIdenticalTo:t];
    [self beginMutation:@"Delete Task"];
    [self.allTasks removeObjectIdenticalTo:t];
    [self recompute];
    [self rebuildRows];
    [self.sidebar reloadData];
    [self.mainTable reloadData];
    if (self.visible.count) {
        NSInteger sel = MIN(row, (NSInteger)self.visible.count - 1);
        if (sel < 0) sel = 0;
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:sel] byExtendingSelection:NO];
    }
    [self updateChrome];
    [self save];
}
- (void)setPriority:(NSInteger)p onTask:(Task *)t {
    if (!t) return;
    [self beginMutation:@"Set Priority"];
    t.priority = p;
    [self refreshAll];
}

- (void)reorderSelectedBy:(NSInteger)dir {
    if (self.searchString.length) { NSBeep(); return; }   /* ambiguous under filter */
    Task *t = [self selectedTask];
    if (!t) return;
    NSInteger vi = (NSInteger)[self.visible indexOfObjectIdenticalTo:t];
    NSInteger ni = vi + dir;
    if (ni < 0 || ni >= (NSInteger)self.visible.count) return;
    Task *neighbor = self.visible[ni];
    [self beginMutation:@"Reorder Task"];
    /* shift (remove + insert), not swap, so hidden/filtered tasks between t and
       its visible neighbor keep their relative order in the global allTasks. */
    [self.allTasks removeObjectIdenticalTo:t];
    NSInteger bi = (NSInteger)[self.allTasks indexOfObjectIdenticalTo:neighbor];
    [self.allTasks insertObject:t atIndex:(dir > 0 ? bi + 1 : bi)];
    [self recompute];
    [self.mainTable reloadData];
    NSInteger idx = (NSInteger)[self.visible indexOfObjectIdenticalTo:t];
    if (idx != NSNotFound)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    [self save];
}

- (void)clearDone {
    NSMutableArray *doomed = [NSMutableArray array];
    for (Task *t in self.visible) if (t.done) [doomed addObject:t];
    if (!doomed.count) { NSBeep(); return; }
    [self beginMutation:@"Clear Completed"];
    for (Task *t in doomed) [self.allTasks removeObjectIdenticalTo:t];
    [self refreshAll];
}

#pragma mark Inline edit

- (void)beginEditSelected {
    NSInteger row = self.mainTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.visible.count) return;
    Task *t = self.visible[row];
    NSView *v = [self.mainTable viewAtColumn:0 row:row makeIfNecessary:YES];
    NSTextField *field = [v isKindOfClass:[NSTableCellView class]]
        ? ((NSTableCellView *)v).textField : nil;
    if (!field) return;
    self.editingTask = t;
    field.editable = YES;
    field.selectable = YES;
    field.stringValue = t.text;   /* edit the bare title, not the attributed form */
    [self.window makeFirstResponder:field];
}

#pragma mark Categories UI

- (NSString *)promptText:(NSString *)title default:(NSString *)def {
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    tf.stringValue = def ?: @"";
    a.accessoryView = tf;
    [a.window setInitialFirstResponder:tf];
    NSModalResponse r = [a runModal];
    if (r != NSAlertFirstButtonReturn) return nil;
    return [tf.stringValue stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
}

- (void)addCategory:(id)sender {
    NSString *name = [self promptText:@"New list name:" default:@""];
    if (!name.length) return;
    if ([self categoryNamed:name]) { NSBeep(); return; }
    [self beginMutation:@"Add List"];
    Category *c = [self ensureCategory:name];
    self.selectedCategory = c;
    [self refreshAll];
    [self selectSidebarForCurrent];
}
- (void)removeSelectedCategory {
    NSInteger r = self.sidebar.selectedRow;
    if (r < 0 || r >= (NSInteger)self.rows.count) { NSBeep(); return; }
    SidebarRow *row = self.rows[r];
    if (row.kind != RowCategory) { NSBeep(); return; }
    if ([row.category.name isEqualToString:@"Inbox"]) { NSBeep(); return; }
    [self beginMutation:@"Delete List"];
    NSString *gone = row.category.name;
    for (Task *t in self.allTasks)
        if ([t.category isEqualToString:gone]) t.category = @"Inbox";
    [self.categories removeObjectIdenticalTo:row.category];
    if ([self.selectedCategory.name isEqualToString:gone]) {
        self.selectedCategory = nil; self.selectedSmart = SmartAll;
    }
    [self refreshAll];
    [self selectSidebarForCurrent];
}
- (void)renameSidebarCategoryAtRow:(NSInteger)r {
    if (r < 0 || r >= (NSInteger)self.rows.count) return;
    SidebarRow *row = self.rows[r];
    if (row.kind != RowCategory || [row.category.name isEqualToString:@"Inbox"]) return;
    NSString *old = row.category.name;
    NSString *name = [self promptText:@"Rename list:" default:old];
    if (!name.length || [name isEqualToString:old]) return;
    Category *clash = [self categoryNamed:name];
    if (clash && clash != row.category) { NSBeep(); return; }   /* allow case-only rename */
    [self beginMutation:@"Rename List"];
    for (Task *t in self.allTasks)
        if ([t.category isEqualToString:old]) t.category = name;
    row.category.name = name;
    if ([self.selectedCategory.name isEqualToString:old]) self.selectedCategory = row.category;
    [self refreshAll];
    [self selectSidebarForCurrent];
}

- (void)selectSidebarForCurrent {
    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        SidebarRow *row = self.rows[i];
        if (self.selectedCategory && row.kind == RowCategory &&
            [row.category.name isEqualToString:self.selectedCategory.name]) {
            [self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            return;
        }
        if (!self.selectedCategory && row.kind == RowSmart && row.smart == self.selectedSmart) {
            [self.sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            return;
        }
    }
}
- (void)jumpToSmart:(SmartKind)s {
    self.selectedCategory = nil; self.selectedSmart = s;
    [self selectSidebarForCurrent];
    [self refreshView];   /* navigation only */
}

#pragma mark Actions wired to menu / buttons

- (void)addAction:(id)sender { [self addFromInput]; }
- (void)clearDoneAction:(id)sender { [self clearDone]; }
- (void)focusSearch:(id)sender { [self.window makeFirstResponder:self.search]; }
- (void)focusInput:(id)sender { [self.window makeFirstResponder:self.input]; }
- (void)newCategoryAction:(id)sender { [self addCategory:sender]; }
- (void)undoAction:(id)sender { [self.undo undo]; }
- (void)redoAction:(id)sender { [self.undo redo]; }
- (void)smart1:(id)sender { [self jumpToSmart:SmartAll]; }
- (void)smart2:(id)sender { [self jumpToSmart:SmartActive]; }
- (void)smart3:(id)sender { [self jumpToSmart:SmartCompleted]; }
- (void)smart4:(id)sender { [self jumpToSmart:SmartFlagged]; }
- (void)filterChanged:(id)sender { self.filterMode = (FilterMode)self.filterSeg.selectedSegment; [self refreshView]; }

#pragma mark Keyboard (KeyTableDelegate)

- (BOOL)keyTable:(NSTableView *)t handleKey:(NSEvent *)e {
    unsigned short kc = e.keyCode;
    NSString *chars = e.charactersIgnoringModifiers;
    BOOL cmd = (e.modifierFlags & NSEventModifierFlagCommand) != 0;

    if (t == self.mainTable) {
        if (cmd && kc == 126) { [self reorderSelectedBy:-1]; return YES; }  /* ⌘↑ */
        if (cmd && kc == 125) { [self reorderSelectedBy:+1]; return YES; }  /* ⌘↓ */
        if (kc == 123) { [self.window makeFirstResponder:self.sidebar]; return YES; } /* ← */
        if (kc == 126 || kc == 125) return NO;   /* ↑/↓ -> native selection */
        Task *sel = [self selectedTask];
        if ([chars isEqualToString:@" "]) { [self toggleTask:sel]; return YES; }
        if (kc == 36) { [self beginEditSelected]; return YES; }              /* Return */
        if (kc == 51 || kc == 117) { [self deleteTask:sel]; return YES; }    /* ⌫ / ⌦ */
        if ([chars isEqualToString:@"1"]) { [self setPriority:1 onTask:sel]; return YES; }
        if ([chars isEqualToString:@"2"]) { [self setPriority:2 onTask:sel]; return YES; }
        if ([chars isEqualToString:@"3"]) { [self setPriority:3 onTask:sel]; return YES; }
        if ([chars isEqualToString:@"0"] || [chars isEqualToString:@"`"]) { [self setPriority:0 onTask:sel]; return YES; }
        return NO;
    }
    if (t == self.sidebar) {
        if (kc == 124) { [self.window makeFirstResponder:self.mainTable]; return YES; } /* → */
        if (kc == 51 || kc == 117) { [self removeSelectedCategory]; return YES; }
        if (kc == 36) { [self renameSidebarCategoryAtRow:self.sidebar.selectedRow]; return YES; }
        if (kc == 126 || kc == 125) return NO;   /* native nav (skips unselectable) */
        return NO;
    }
    return NO;
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return tv == self.sidebar ? (NSInteger)self.rows.count : (NSInteger)self.visible.count;
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    if (tv != self.sidebar) return YES;
    SidebarRow *r = self.rows[row];
    return r.kind == RowSmart || r.kind == RowCategory;
}
- (BOOL)tableView:(NSTableView *)tv isGroupRow:(NSInteger)row {
    if (tv != self.sidebar) return NO;
    return self.rows[row].kind == RowHeader;
}
- (CGFloat)tableView:(NSTableView *)tv heightOfRow:(NSInteger)row {
    if (tv != self.sidebar) return 30;
    switch (self.rows[row].kind) {
        case RowHeader: return 22;
        case RowSeparator: return 10;
        default: return 28;
    }
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (tv == self.sidebar) return [self sidebarViewForRow:row];
    return [self taskViewForRow:row];
}

- (NSView *)sidebarViewForRow:(NSInteger)row {
    SidebarRow *r = self.rows[row];

    if (r.kind == RowSeparator) {
        NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
        return v;
    }
    if (r.kind == RowHeader) {
        NSTextField *h = [NSTextField labelWithString:r.title.uppercaseString];
        h.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        h.textColor = NSColor.secondaryLabelColor;
        return h;
    }

    SidebarCellView *cell = [self.sidebar makeViewWithIdentifier:@"side" owner:self];
    NSTextField *lead, *title, *badge;
    if (!cell) {
        cell = [[SidebarCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"side";
        lead = [NSTextField labelWithString:@""];
        title = [NSTextField labelWithString:@""];
        badge = [NSTextField labelWithString:@""];
        cell.lead = lead; cell.titleField = title; cell.badge = badge;
        badge.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        badge.textColor = NSColor.secondaryLabelColor;
        badge.alignment = NSTextAlignmentRight;
        title.font = [NSFont systemFontOfSize:13];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        for (NSTextField *f in @[lead, title, badge]) {
            f.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:f];
        }
        cell.textField = title;
        [NSLayoutConstraint activateConstraints:@[
            [lead.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [lead.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [lead.widthAnchor constraintEqualToConstant:18],
            [title.leadingAnchor constraintEqualToAnchor:lead.trailingAnchor constant:4],
            [title.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [badge.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:4],
            [badge.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [badge.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        [title setContentHuggingPriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [badge setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else {
        lead = cell.lead; title = cell.titleField; badge = cell.badge;
    }

    if (r.kind == RowCategory) {
        lead.attributedStringValue = [[NSAttributedString alloc] initWithString:@"●"
            attributes:@{ NSForegroundColorAttributeName: PaletteColor(r.category.colorIndex),
                          NSFontAttributeName: [NSFont systemFontOfSize:11] }];
    } else {
        lead.attributedStringValue = [[NSAttributedString alloc] initWithString:r.glyph
            attributes:@{ NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
                          NSFontAttributeName: [NSFont systemFontOfSize:13] }];
    }
    title.stringValue = r.title;
    title.textColor = NSColor.labelColor;
    NSInteger n = [self countForSidebarRow:r];
    badge.stringValue = n ? [NSString stringWithFormat:@"%ld", (long)n] : @"";
    return cell;
}

- (NSString *)relativeDue:(NSDate *)due {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    NSDateComponents *c = [cal components:NSCalendarUnitDay fromDate:today
                                   toDate:[cal startOfDayForDate:due] options:0];
    NSInteger d = c.day;
    if (d == 0) return @"Today";
    if (d == 1) return @"Tomorrow";
    if (d == -1) return @"Yesterday";
    if (d > 1 && d < 7) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"EEE";
        return [f stringFromDate:due];
    }
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MMM d";
    return [f stringFromDate:due];
}

- (NSView *)taskViewForRow:(NSInteger)row {
    Task *t = self.visible[row];
    TaskCellView *cell = [self.mainTable makeViewWithIdentifier:@"task" owner:self];
    BarView *bar; CheckboxView *check; NSTextField *title, *due, *tag;

    if (!cell) {
        cell = [[TaskCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"task";
        bar = [[BarView alloc] initWithFrame:NSZeroRect];
        check = [[CheckboxView alloc] initWithFrame:NSZeroRect];
        title = [NSTextField labelWithString:@""];
        due = [NSTextField labelWithString:@""];
        tag = [NSTextField labelWithString:@""];
        cell.bar = bar; cell.check = check; cell.titleField = title;
        cell.dueField = due; cell.tagField = tag;
        title.font = [NSFont systemFontOfSize:14];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        due.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        tag.font = [NSFont systemFontOfSize:10];
        tag.textColor = NSColor.tertiaryLabelColor;
        for (NSView *v in @[bar, check, title, due, tag]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:v];
        }
        cell.textField = title;
        [NSLayoutConstraint activateConstraints:@[
            [bar.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [bar.topAnchor constraintEqualToAnchor:cell.topAnchor constant:3],
            [bar.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-3],
            [bar.widthAnchor constraintEqualToConstant:3],
            [check.leadingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:10],
            [check.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [check.widthAnchor constraintEqualToConstant:18],
            [check.heightAnchor constraintEqualToConstant:18],
            [title.leadingAnchor constraintEqualToAnchor:check.trailingAnchor constant:8],
            [title.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [tag.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8],
            [tag.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [due.leadingAnchor constraintEqualToAnchor:tag.trailingAnchor constant:8],
            [due.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
            [due.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        [title setContentHuggingPriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [title setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [due setContentHuggingPriority:760 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [tag setContentHuggingPriority:755 forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else {
        bar = cell.bar; check = cell.check; title = cell.titleField;
        due = cell.dueField; tag = cell.tagField;
    }

    /* fully reset reused cell state */
    bar.level = t.priority; [bar setNeedsDisplay:YES];
    check.on = t.done; check.priority = t.priority; [check setNeedsDisplay:YES];

    __weak AppController *weakSelf = self;
    Task *captured = t;
    check.onToggle = ^{ [weakSelf toggleTask:captured]; };

    title.editable = NO; title.selectable = NO;
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFontAttributeName] = [NSFont systemFontOfSize:14];
    if (t.done) {
        attrs[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
        attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    } else {
        attrs[NSForegroundColorAttributeName] = NSColor.labelColor;
    }
    title.attributedStringValue = [[NSAttributedString alloc]
        initWithString:t.text ?: @"" attributes:attrs];

    if (t.due) {
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *today = [cal startOfDayForDate:[NSDate date]];
        BOOL overdue = !t.done && [t.due compare:today] == NSOrderedAscending;
        due.stringValue = [self relativeDue:t.due];
        due.textColor = overdue ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
        due.hidden = NO;
    } else {
        due.stringValue = @""; due.hidden = YES;
    }

    BOOL showTag = (self.selectedCategory == nil);   /* show category in smart lists */
    tag.stringValue = showTag ? t.category : @"";
    tag.hidden = !showTag || t.category.length == 0;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if (note.object != self.sidebar) { [self updateChrome]; return; }
    NSInteger r = self.sidebar.selectedRow;
    if (r < 0 || r >= (NSInteger)self.rows.count) return;
    SidebarRow *row = self.rows[r];
    if (row.kind == RowSmart) { self.selectedCategory = nil; self.selectedSmart = row.smart; }
    else if (row.kind == RowCategory) { self.selectedCategory = row.category; }
    else return;
    [self recompute];
    [self.mainTable reloadData];
    if (self.visible.count)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateChrome];
}

- (void)mainDoubleClick:(id)sender {
    [self beginEditSelected];
}

#pragma mark NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == self.search) {
        self.searchString = self.search.stringValue;
        [self refreshView];   /* search doesn't mutate the model — no disk write */
    }
}
- (void)controlTextDidEndEditing:(NSNotification *)note {
    NSControl *ctl = note.object;
    NSInteger movement = [note.userInfo[@"NSTextMovement"] integerValue];

    if (ctl == self.input) {
        if (movement == NSReturnTextMovement) [self addFromInput];
        return;
    }
    if (ctl == self.search) return;

    /* inline task edit — edits ONLY the title, as a literal string. We do NOT
       re-run quick-add parsing here (that would silently strip @/!/date words
       and partially mutate category/priority/due). Commit only on a deliberate
       Return/Tab; movement 0 means a programmatic teardown (e.g. a reload while
       editing) or click-away, which we discard rather than commit half-typed text. */
    if (self.editingTask) {
        NSTextField *field = (NSTextField *)ctl;
        Task *t = self.editingTask;
        self.editingTask = nil;
        field.editable = NO; field.selectable = NO;
        BOOL commit = (movement == NSReturnTextMovement
                    || movement == NSTabTextMovement
                    || movement == NSBacktabTextMovement);
        if (commit) {
            NSString *raw = [field.stringValue
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (raw.length && ![raw isEqualToString:t.text]) {
                [self beginMutation:@"Edit Task"];
                t.text = raw;
            }
        }
        [self refreshAll];   /* restores the cell's attributed (struck-through) display */
        [self.window makeFirstResponder:self.mainTable];
    }
}

#pragma mark NSSplitViewDelegate (clamp sidebar width)

- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return 165; }
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return 300; }
- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)v { return NO; }

#pragma mark Undo manager wiring

/* Deliberately DO NOT expose the task-snapshot undo manager to the window: that
   would let text fields register per-keystroke text-undo onto the same stack as
   task snapshots, so ⌘Z could revert the whole task list while typing. Task
   undo/redo is driven only through the Edit-menu items -> [self.undo undo/redo]. */
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window { return nil; }

#pragma mark UI construction

- (NSButton *)smallButton:(NSString *)title action:(SEL)sel {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:sel];
    b.bezelStyle = NSBezelStyleRounded;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

- (void)buildUI {
    NSRect frame = NSMakeRect(0, 0, 860, 560);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                       NSWindowStyleMaskFullSizeContentView;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Todo";
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(720, 420);
    self.window.delegate = (id)self;
    [self.window setFrameAutosaveName:@"TodoMainWindow"];
    [self.window center];

    /* ---- split view ---- */
    self.split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    self.split.vertical = YES;
    self.split.dividerStyle = NSSplitViewDividerStyleThin;
    self.split.delegate = self;
    self.split.translatesAutoresizingMaskIntoConstraints = NO;
    self.split.autosaveName = @"TodoSplit";

    /* ---- sidebar pane (frosted) ---- */
    NSVisualEffectView *side = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    side.material = NSVisualEffectMaterialSidebar;
    side.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    side.state = NSVisualEffectStateActive;
    side.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *sideScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    sideScroll.drawsBackground = NO;
    sideScroll.hasVerticalScroller = YES;
    sideScroll.borderType = NSNoBorder;
    sideScroll.translatesAutoresizingMaskIntoConstraints = NO;

    self.sidebar = [[KeyTable alloc] initWithFrame:NSZeroRect];
    self.sidebar.keyHandler = self;
    self.sidebar.headerView = nil;
    self.sidebar.backgroundColor = NSColor.clearColor;
    self.sidebar.rowHeight = 28;
    self.sidebar.dataSource = self;
    self.sidebar.delegate = self;
    self.sidebar.allowsEmptySelection = NO;
    self.sidebar.doubleAction = @selector(sidebarDoubleClick:);
    self.sidebar.target = self;
    if (@available(macOS 11.0, *)) self.sidebar.style = NSTableViewStyleSourceList;
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.sidebar.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
#pragma clang diagnostic pop
    }
    NSTableColumn *sc = [[NSTableColumn alloc] initWithIdentifier:@"s"];
    sc.resizingMask = NSTableColumnAutoresizingMask;
    [self.sidebar addTableColumn:sc];
    sideScroll.documentView = self.sidebar;

    NSButton *plus = [self smallButton:@"+" action:@selector(addCategory:)];
    NSButton *minus = [self smallButton:@"–" action:@selector(removeCategoryAction:)];
    plus.bezelStyle = NSBezelStyleSmallSquare;
    minus.bezelStyle = NSBezelStyleSmallSquare;

    [side addSubview:sideScroll];
    [side addSubview:plus];
    [side addSubview:minus];
    [NSLayoutConstraint activateConstraints:@[
        [sideScroll.topAnchor constraintEqualToAnchor:side.topAnchor constant:28],
        [sideScroll.leadingAnchor constraintEqualToAnchor:side.leadingAnchor],
        [sideScroll.trailingAnchor constraintEqualToAnchor:side.trailingAnchor],
        [plus.leadingAnchor constraintEqualToAnchor:side.leadingAnchor constant:6],
        [plus.bottomAnchor constraintEqualToAnchor:side.bottomAnchor constant:-6],
        [plus.widthAnchor constraintEqualToConstant:28],
        [minus.leadingAnchor constraintEqualToAnchor:plus.trailingAnchor constant:2],
        [minus.bottomAnchor constraintEqualToAnchor:side.bottomAnchor constant:-6],
        [minus.widthAnchor constraintEqualToConstant:28],
        [sideScroll.bottomAnchor constraintEqualToAnchor:plus.topAnchor constant:-6],
    ]];

    /* ---- main pane ---- */
    NSView *main = [[NSView alloc] initWithFrame:NSZeroRect];
    main.translatesAutoresizingMaskIntoConstraints = NO;

    self.headerLabel = [NSTextField labelWithString:@"All"];
    self.headerLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.search.placeholderString = @"Search";
    self.search.delegate = self;
    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    [self.search.widthAnchor constraintEqualToConstant:200].active = YES;

    self.filterSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"All", @"Active", @"Done"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self action:@selector(filterChanged:)];
    self.filterSeg.selectedSegment = 0;
    self.filterSeg.translatesAutoresizingMaskIntoConstraints = NO;

    self.input = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.input.placeholderString = @"Add a task…   @list  !!  tomorrow";
    self.input.bezelStyle = NSTextFieldRoundedBezel;
    self.input.font = [NSFont systemFontOfSize:14];
    self.input.delegate = self;
    self.input.translatesAutoresizingMaskIntoConstraints = NO;

    self.prioPop = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.prioPop addItemsWithTitles:@[@"—", @"!", @"!!", @"!!!"]];
    self.prioPop.translatesAutoresizingMaskIntoConstraints = NO;
    [self.prioPop.widthAnchor constraintEqualToConstant:60].active = YES;

    NSButton *addBtn = [self smallButton:@"Add" action:@selector(addAction:)];
    [addBtn.widthAnchor constraintEqualToConstant:70].active = YES;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    self.mainTable = [[KeyTable alloc] initWithFrame:NSZeroRect];
    self.mainTable.keyHandler = self;
    self.mainTable.headerView = nil;
    self.mainTable.rowHeight = 30;
    self.mainTable.intercellSpacing = NSMakeSize(0, 4);
    self.mainTable.dataSource = self;
    self.mainTable.delegate = self;
    self.mainTable.doubleAction = @selector(mainDoubleClick:);
    self.mainTable.target = self;
    NSTableColumn *mc = [[NSTableColumn alloc] initWithIdentifier:@"t"];
    mc.resizingMask = NSTableColumnAutoresizingMask;
    [self.mainTable addTableColumn:mc];
    scroll.documentView = self.mainTable;

    self.placeholder = [NSTextField labelWithString:@""];
    self.placeholder.font = [NSFont systemFontOfSize:14];
    self.placeholder.textColor = NSColor.tertiaryLabelColor;
    self.placeholder.alignment = NSTextAlignmentCenter;
    self.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholder.maximumNumberOfLines = 3;

    self.status = [NSTextField labelWithString:@""];
    self.status.textColor = NSColor.secondaryLabelColor;
    self.status.font = [NSFont systemFontOfSize:11];
    self.status.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *clearBtn = [self smallButton:@"Clear Done" action:@selector(clearDoneAction:)];

    for (NSView *v in @[self.headerLabel, self.search, self.filterSeg, self.input,
                        self.prioPop, addBtn, scroll, self.placeholder, self.status, clearBtn])
        [main addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        /* header row */
        [self.headerLabel.topAnchor constraintEqualToAnchor:main.topAnchor constant:28],
        [self.headerLabel.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:20],
        [self.search.centerYAnchor constraintEqualToAnchor:self.headerLabel.centerYAnchor],
        [self.search.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        /* filter row */
        [self.filterSeg.topAnchor constraintEqualToAnchor:self.headerLabel.bottomAnchor constant:12],
        [self.filterSeg.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        /* add row */
        [self.input.topAnchor constraintEqualToAnchor:self.filterSeg.bottomAnchor constant:12],
        [self.input.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [self.input.heightAnchor constraintEqualToConstant:24],
        [self.prioPop.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [self.prioPop.leadingAnchor constraintEqualToAnchor:self.input.trailingAnchor constant:8],
        [addBtn.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [addBtn.leadingAnchor constraintEqualToAnchor:self.prioPop.trailingAnchor constant:8],
        [addBtn.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        /* list */
        [scroll.topAnchor constraintEqualToAnchor:self.input.bottomAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        /* status row */
        [self.status.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:8],
        [self.status.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [self.status.bottomAnchor constraintEqualToAnchor:main.bottomAnchor constant:-12],
        [clearBtn.centerYAnchor constraintEqualToAnchor:self.status.centerYAnchor],
        [clearBtn.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:self.status.topAnchor constant:-8],
        /* placeholder centered over list */
        [self.placeholder.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [self.placeholder.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],
    ]];

    [self.split addArrangedSubview:side];
    [self.split addArrangedSubview:main];
    [self.split setHoldingPriority:NSLayoutPriorityDefaultLow + 1 forSubviewAtIndex:0];
    [side.widthAnchor constraintGreaterThanOrEqualToConstant:165].active = YES;

    self.window.contentView = [[NSView alloc] initWithFrame:frame];
    [self.window.contentView addSubview:self.split];
    [NSLayoutConstraint activateConstraints:@[
        [self.split.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
        [self.split.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor],
        [self.split.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
        [self.split.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
    ]];

    /* initial sidebar width */
    [self.split setPosition:200 ofDividerAtIndex:0];
}

- (void)sidebarDoubleClick:(id)sender {
    [self renameSidebarCategoryAtRow:self.sidebar.clickedRow];
}
- (void)removeCategoryAction:(id)sender { [self removeSelectedCategory]; }

#pragma mark App lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.undo = [NSUndoManager new];
    self.selectedSmart = SmartAll;
    self.filterMode = FilterAll;
    self.searchString = @"";
    self.dbPath = [self resolveDBPath];
    [self load];

    [self buildUI];
    [self rebuildRows];
    [self recompute];
    [self.sidebar reloadData];
    [self.mainTable reloadData];
    [self selectSidebarForCurrent];
    if (self.visible.count)
        [self.mainTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateChrome];

    /* key-view loop: input -> list -> sidebar -> search -> input */
    self.input.nextKeyView = self.mainTable;
    self.mainTable.nextKeyView = self.sidebar;
    self.sidebar.nextKeyView = self.search;
    self.search.nextKeyView = self.input;
    self.window.initialFirstResponder = self.mainTable;

    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.mainTable];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
- (void)applicationWillTerminate:(NSNotification *)note { [self save]; }

@end

#pragma mark - Menu + main

static NSMenuItem *Item(NSMenu *m, NSString *title, SEL action, NSString *key, NSUInteger mods, id target) {
    NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    it.keyEquivalentModifierMask = mods;
    if (target) it.target = target;
    [m addItem:it];
    return it;
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppController *controller = [AppController new];
        app.delegate = controller;

        NSMenu *menubar = [NSMenu new];
        app.mainMenu = menubar;
        NSUInteger CMD = NSEventModifierFlagCommand;
        NSUInteger CMDSH = NSEventModifierFlagCommand | NSEventModifierFlagShift;

        /* App menu */
        NSMenuItem *appItem = [NSMenuItem new];
        [menubar addItem:appItem];
        NSMenu *appMenu = [NSMenu new];
        Item(appMenu, @"Quit Todo", @selector(terminate:), @"q", CMD, nil);
        appItem.submenu = appMenu;

        /* Edit menu */
        NSMenuItem *editItem = [NSMenuItem new];
        [menubar addItem:editItem];
        NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        Item(editMenu, @"Undo", @selector(undoAction:), @"z", CMD, controller);
        Item(editMenu, @"Redo", @selector(redoAction:), @"z", CMDSH, controller);
        [editMenu addItem:[NSMenuItem separatorItem]];
        Item(editMenu, @"Cut", @selector(cut:), @"x", CMD, nil);
        Item(editMenu, @"Copy", @selector(copy:), @"c", CMD, nil);
        Item(editMenu, @"Paste", @selector(paste:), @"v", CMD, nil);
        Item(editMenu, @"Select All", @selector(selectAll:), @"a", CMD, nil);
        [editMenu addItem:[NSMenuItem separatorItem]];
        Item(editMenu, @"Find", @selector(focusSearch:), @"f", CMD, controller);
        editItem.submenu = editMenu;

        /* View menu */
        NSMenuItem *viewItem = [NSMenuItem new];
        [menubar addItem:viewItem];
        NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
        Item(viewMenu, @"All", @selector(smart1:), @"1", CMD, controller);
        Item(viewMenu, @"Active", @selector(smart2:), @"2", CMD, controller);
        Item(viewMenu, @"Completed", @selector(smart3:), @"3", CMD, controller);
        Item(viewMenu, @"Flagged", @selector(smart4:), @"4", CMD, controller);
        viewItem.submenu = viewMenu;

        /* List menu */
        NSMenuItem *listItem = [NSMenuItem new];
        [menubar addItem:listItem];
        NSMenu *listMenu = [[NSMenu alloc] initWithTitle:@"List"];
        Item(listMenu, @"New Task", @selector(focusInput:), @"n", CMD, controller);
        Item(listMenu, @"New List", @selector(newCategoryAction:), @"n", CMDSH, controller);
        Item(listMenu, @"Clear Completed", @selector(clearDoneAction:), @"", CMD, controller);
        listItem.submenu = listMenu;

        [app run];
    }
    return 0;
}
