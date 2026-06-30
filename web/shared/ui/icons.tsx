// Ícones SVG (lucide-react) — substituem os emojis. Herdam currentColor (respeitam tokens).
import {
  Home, Users, User, Trophy, MessageSquareQuote, Library, PenLine, GraduationCap, Tag, Wrench,
  Settings, Mail, Calendar, CalendarDays, ClipboardList, Check, CircleCheck, X, TriangleAlert,
  ChevronDown, ChevronUp, ChevronRight, ChevronLeft, ArrowRight, ArrowLeft, ArrowUp, ArrowDown,
  ArrowUpRight, Search, Sun, Moon, Menu, RefreshCw, RotateCw, Link2, Pause, Play, Lock, Download,
  Mic, Camera, Clapperboard, Truck, NotebookPen, FileText, PartyPopper, Hand, Star, Circle, Sprout,
  Briefcase, Medal, Coins, Gem, LogOut, Plus, Trash2, Pencil, Inbox, Copy, type LucideIcon,
} from 'lucide-react';

const MAP: Record<string, LucideIcon> = {
  // navegação
  home: Home, alunos: Users, users: Users, user: User, placas: Trophy, trophy: Trophy,
  depoimentos: MessageSquareQuote, biblioteca: Library, cursos: GraduationCap,
  tags: Tag, pen: PenLine, 'admin-dev': Wrench, wrench: Wrench, settings: Settings, config: Settings,
  solicitacoes: Mail, mail: Mail, inbox: Inbox, calendar: Calendar, 'calendar-days': CalendarDays,
  clipboard: ClipboardList,
  // ações / estados
  check: Check, 'check-circle': CircleCheck, x: X, close: X, alert: TriangleAlert, copy: Copy,
  search: Search, refresh: RefreshCw, rotate: RotateCw, link: Link2, pause: Pause, play: Play,
  lock: Lock, download: Download, logout: LogOut, plus: Plus, trash: Trash2, pencil: Pencil,
  star: Star, circle: Circle, party: PartyPopper, wave: Hand, file: FileText, notebook: NotebookPen,
  mic: Mic, camera: Camera, film: Clapperboard, truck: Truck,
  // setas / chevrons
  'chevron-down': ChevronDown, 'chevron-up': ChevronUp, 'chevron-right': ChevronRight,
  'chevron-left': ChevronLeft, 'arrow-right': ArrowRight, 'arrow-left': ArrowLeft,
  'arrow-up': ArrowUp, 'arrow-down': ArrowDown, 'arrow-up-right': ArrowUpRight,
  // tema
  sun: Sun, moon: Moon, menu: Menu,
  // níveis (metal/pedra)
  sprout: Sprout, briefcase: Briefcase, medal: Medal, coins: Coins, gem: Gem,
};

export function Icon({ name, size = 16, className, strokeWidth = 2, style }: {
  name: string; size?: number; className?: string; strokeWidth?: number; style?: React.CSSProperties;
}) {
  const C = MAP[name];
  if (!C) return null;
  return <C size={size} strokeWidth={strokeWidth} className={className} style={style} aria-hidden />;
}
