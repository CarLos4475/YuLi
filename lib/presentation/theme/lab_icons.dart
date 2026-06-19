// YuLi Icon System — Lucide icons via lucide_icons_flutter.
// Usage:  Icon(YuLiIcons.close, size: 20, color: ...)
//
// Gradually replace Icon(Icons.xxx) with Icon(YuLiIcons.xxx).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class YuLiIcons {
  YuLiIcons._();

  // ─── Navigation ──────────────────────────────────────────────
  static const IconData close = LucideIcons.x;
  static const IconData arrowLeft = LucideIcons.arrowLeft;
  static const IconData arrowRight = LucideIcons.arrowRight;
  static const IconData arrowUp = LucideIcons.arrowUp;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData moreHorizontal = LucideIcons.moreHorizontal;
  static const IconData home = LucideIcons.home;

  // ─── Actions ─────────────────────────────────────────────────
  static const IconData check = LucideIcons.check;
  static const IconData plus = LucideIcons.plus;
  static const IconData minus = LucideIcons.minus;
  static const IconData search = LucideIcons.search;
  static const IconData settings = LucideIcons.settings;
  static const IconData trash = LucideIcons.trash2;
  static const IconData pen = LucideIcons.pen;
  static const IconData share = LucideIcons.share2;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData link = LucideIcons.link;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData globe = LucideIcons.globe;
  static const IconData eye = LucideIcons.eye;
  static const IconData undo = LucideIcons.undo;
  static const IconData redo = LucideIcons.redo;
  static const IconData rotateCcw = LucideIcons.rotateCcw;
  static const IconData rotateCw = LucideIcons.rotateCw;
  static const IconData copy = LucideIcons.copy;
  static const IconData clipboard = LucideIcons.clipboard;
  static const IconData flipHorizontal = LucideIcons.flipHorizontal;
  static const IconData menu = LucideIcons.menu;
  static const IconData flipVertical = LucideIcons.flipVertical;

  // ─── Drawing / Canvas Tools ──────────────────────────────────
  static const IconData penLine = LucideIcons.penLine;
  static const IconData penTool = LucideIcons.penTool;
  static const IconData pencil = LucideIcons.pencil;
  static const IconData highlighter = LucideIcons.highlighter;
  static const IconData hand = LucideIcons.hand;
  static const IconData lock = LucideIcons.lock;
  static const IconData lockOpen = LucideIcons.lockOpen;
  static const IconData layoutGrid = LucideIcons.layoutGrid;
  static const IconData sparkles = LucideIcons.sparkles;
  static const IconData wandSparkles = LucideIcons.wandSparkles;
  static const IconData slidersHorizontal = LucideIcons.slidersHorizontal;
  static const IconData paintBucket = LucideIcons.paintBucket;
  static const IconData palette = LucideIcons.palette;
  static const IconData crop = LucideIcons.crop;
  static const IconData eraser = LucideIcons.eraser;
  static const IconData lasso = LucideIcons.lasso;
  static const IconData squareDashedMousePointer =
      LucideIcons.squareDashedMousePointer;
  static const IconData mousePointer = LucideIcons.mousePointer2;
  static const IconData shapes = LucideIcons.shapes;
  static const IconData circle = LucideIcons.circle;
  static const IconData triangle = LucideIcons.triangle;

  // ─── Content / Media ─────────────────────────────────────────
  static const IconData image = LucideIcons.image;
  static const IconData images = LucideIcons.images;
  static const IconData camera = LucideIcons.camera;
  static const IconData fileText = LucideIcons.fileText;
  static const IconData textInitial = LucideIcons.textInitial;
  static const IconData box = LucideIcons.box;

  // ─── Lab / Kanban ────────────────────────────────────────────
  static const IconData calendar = LucideIcons.calendar;
  static const IconData calendarDays = LucideIcons.calendarDays;
  static const IconData clock = LucideIcons.clock;
  static const IconData timer = LucideIcons.timer;
  static const IconData bell = LucideIcons.bell;
  static const IconData bellRing = LucideIcons.bellRing;
  static const IconData kanban = LucideIcons.kanban;
  static const IconData listChecks = LucideIcons.listChecks;
  static const IconData square = LucideIcons.square;
  static const IconData squareCheck = LucideIcons.squareCheck;
  static const IconData xSquare = LucideIcons.xSquare;
  static const IconData circleCheck = LucideIcons.circleCheck;
  static const IconData triangleAlert = LucideIcons.triangleAlert;
  static const IconData play = LucideIcons.play;
  static const IconData circlePlay = LucideIcons.circlePlay;
  static const IconData pause = LucideIcons.pause;
  static const IconData archive = LucideIcons.archive;

  // ─── Folder / File ───────────────────────────────────────────
  static const IconData folder = LucideIcons.folder;
  static const IconData notebook = LucideIcons.notebook;
  static const IconData bookmark = LucideIcons.bookmark;
  static const IconData tag = LucideIcons.tag;

  // ─── AI / Lab ────────────────────────────────────────────────
  static const IconData flaskConical = LucideIcons.flaskConical;
  static const IconData messageSquare = LucideIcons.messageSquare;
  static const IconData info = LucideIcons.info;
  static const IconData helpCircle = LucideIcons.helpCircle;
  static const IconData bug = LucideIcons.bug;
  // YuLi AI chat modes (skills).
  static const IconData scale = LucideIcons.scale;
  static const IconData graduationCap = LucideIcons.graduationCap;
  static const IconData lightbulb = LucideIcons.lightbulb;
  static const IconData brain = LucideIcons.brain;

  // ─── Misc ────────────────────────────────────────────────────
  static const IconData pin = LucideIcons.pin;
  static const IconData mapPin = LucideIcons.mapPin;
  static const IconData infinity = LucideIcons.infinity;
  static const IconData scan = LucideIcons.scan;
  static const IconData maximize = LucideIcons.maximize;
  static const IconData discAlbum = LucideIcons.discAlbum;
  static const IconData filter = LucideIcons.filter;
  static const IconData timeline = LucideIcons.timeline;
  static const IconData star = LucideIcons.star;
  static const IconData dice = LucideIcons.dices;
  static const IconData dice5 = LucideIcons.dice5;
  static const IconData gripVertical = LucideIcons.gripVertical;
  static const IconData gitGraph = LucideIcons.gitGraph;
  static const IconData bookOpen = LucideIcons.bookOpen;
  static const IconData scissors = LucideIcons.scissors;

  // ─── Text editor ─────────────────────────────────────────────
  static const IconData type = LucideIcons.type;
  static const IconData code = LucideIcons.code;
  static const IconData table = LucideIcons.table;
  static const IconData textQuote = LucideIcons.textQuote;
  static const IconData textAlignStart = LucideIcons.textAlignStart;
  static const IconData textAlignCenter = LucideIcons.textAlignCenter;
  static const IconData textAlignEnd = LucideIcons.textAlignEnd;
  static const IconData sigma = LucideIcons.sigma;
  static const IconData lineSquiggle = LucideIcons.lineSquiggle;
  static const IconData fileCode = LucideIcons.fileCode;

  // ─── Status / Alerts ─────────────────────────────────────────
  static const IconData checkCheck = LucideIcons.checkCheck;
  static const IconData imageOff = LucideIcons.imageOff;

  // ─── Fight mode ──────────────────────────────────────────────
  static const IconData layoutDashboard = LucideIcons.layoutDashboard;

  // ─── Lab-specific ────────────────────────────────────────────
  static const IconData notebookText = LucideIcons.notebookText;
  static const IconData brushCleaning = LucideIcons.brushCleaning;
  static const IconData separatorHorizontal = LucideIcons.separatorHorizontal;
}
