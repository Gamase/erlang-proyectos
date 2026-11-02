---
name: Clinical Clarity Mobile System
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#3f4947'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#6f7977'
  outline-variant: '#bec9c6'
  surface-tint: '#1f6961'
  primary: '#00453e'
  on-primary: '#ffffff'
  primary-container: '#0d5e56'
  on-primary-container: '#8fd5ca'
  inverse-primary: '#8ed3c9'
  secondary: '#0051d5'
  on-secondary: '#ffffff'
  secondary-container: '#316bf3'
  on-secondary-container: '#fefcff'
  tertiary: '#800008'
  on-tertiary: '#ffffff'
  tertiary-container: '#ac000f'
  on-tertiary-container: '#ffb6ae'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#a9f0e5'
  primary-fixed-dim: '#8ed3c9'
  on-primary-fixed: '#00201d'
  on-primary-fixed-variant: '#005049'
  secondary-fixed: '#dbe1ff'
  secondary-fixed-dim: '#b4c5ff'
  on-secondary-fixed: '#00174b'
  on-secondary-fixed-variant: '#003ea8'
  tertiary-fixed: '#ffdad6'
  tertiary-fixed-dim: '#ffb4ab'
  on-tertiary-fixed: '#410002'
  on-tertiary-fixed-variant: '#93000b'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-stat:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 38px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  headline-sm:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.04em
  numeric-bed:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: -0.01em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 0.75rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

This design system is engineered for the high-stress, rapid-decision environments of Mexican public health institutions (IMSS, ISSSTE, SSA). It prioritizes utilitarian clarity, instant visual triage, and fatigue reduction for nurses, triage officers, and bed management coordinators working demanding rotational shifts under varying hospital lighting.

The visual direction follows **Modern Clinical Utility**: 
- High legibility and contrast over decorative elements.
- Clean, clinical surfaces grounded in pale cool slates to avoid eye strain compared to pure harsh whites.
- Unambiguous visual encoding using established medical status paradigms to eliminate operational misinterpretation.
- Tactile, finger-friendly mobile touch targets adapted for gloved or fast single-hand interactions in triage stations and triage carts.

## Colors

The palette draws its foundation from Mexican institutional healthcare tones—anchored by an authoritative deep clinical teal-green as primary institutional identity, balanced with distinct functional state colors.

### Base Surfaces & Content
- **Canvas / App Background**: `#F8FAFC` (Slate 50)
- **Card / Surface Container**: `#FFFFFF` (Pure White)
- **Subtle Surface Tint**: `#F1F5F9` (Slate 100)
- **Text Primary**: `#0F172A` (Slate 900) - WCAG AAA ratio on white
- **Text Secondary**: `#475569` (Slate 600)
- **Text Muted / Placeholders**: `#94A3B8` (Slate 400)
- **Card & Divider Border**: `#E2E8F0` (Slate 200)

### Bed Status State Tokens (Matriz de Camas)
- **Cama libre (Available)**:
  - Text & Icon: `#16A34A`
  - Accent / Border: `#22C55E`
  - Background Fill: `#DCFCE7`
- **Cama ocupada (Occupied)**:
  - Text & Icon: `#1D4ED8`
  - Accent / Border: `#2563EB`
  - Background Fill: `#DBEAFE`
- **Cama por limpiar (Pending Cleaning / Dirty)**:
  - Text & Icon: `#B45309`
  - Accent / Border: `#D97706`
  - Background Fill: `#FEF3C7`
- **Cama bloqueada (Blocked / Maintenance)**:
  - Text & Icon: `#475569`
  - Accent / Border: `#64748B`
  - Background Fill: `#F1F5F9`

### Service Occupancy Tiers (Capacidad del Servicio)
- **Normal (< 75%)**: Solid `#16A34A` text/bar, soft `#DCFCE7` track.
- **Advertencia (75% - 84%)**: Solid `#D97706` text/bar, soft `#FEF3C7` track.
- **Crítico (≥ 85%)**: Solid `#DC2626` text/bar, alert background `#FEE2E2`, pulse indicator `#EF4444`.

## Typography

The design system uses **Inter** across all roles to ensure universal rendering on low-tier mobile hospital devices, high legibility of alphanumeric hospital bed identifiers (e.g., `CAM-302-B`, `URG-04`), and distinct numerical figures via tabular numbers (`tnum` OpenType feature enabled by default).

### Role Hierarchy
- **display-stat**: Primary capacity figures (e.g., `92%`, `18/20`) displayed on dashboard heads.
- **numeric-bed**: Heavy emphasis on bed room/number codes, readable at arm's length.
- **headline-lg & md**: Service names (e.g., *Medicina Interna*, *Triage Adultos*), modal heads.
- **body-md & sm**: Patient details (NSS, triage tags, clinical observations).
- **label-md & sm**: Status badges, time elapsed since admission, filter toggles. Rendered in uppercase or bold weights for high-stress scannability.

## Layout & Spacing

The layout is built for **mobile portrait (360px - 430px base)** with fluid column distribution and a rigid 4px/8px modular rhythm.

### Grid & Margins
- **Screen Margins**: Fixed `16px` (`margin`) outer edge gutters on phone screens to prevent thumb occlusion while maximizing screen real estate.
- **Bed Matrix Grid**: 2-column or 3-column fluid grid depending on screen width, with `12px` (`gutter`) row and column spacing for rapid visual separation between unit beds.
- **Compact List Padding**: Cards utilize `12px` (`space-md`) internal padding to optimize vertical density without feeling crowded.
- **Touch Boundaries**: All interactive targets adhere to a minimum bounding box of `48px × 48px`, regardless of the visual element's size.

## Elevation & Depth

This system avoids heavy, muddy drop shadows that reduce contrast under fluorescent hospital fixtures. Instead, it pairs structural crisp borders (`1px solid #E2E8F0`) with faint, cool-tinted ambient shadows to provide subtle physical separation.

### Surface Tiers
- **Tier 0 (Base Canvas)**: `#F8FAFC`, flat.
- **Tier 1 (Clinical Cards & Cells)**: `#FFFFFF`, `border: 1px solid #E2E8F0`, shadow: `0px 1px 3px rgba(15, 23, 42, 0.05), 0px 1px 2px rgba(15, 23, 42, 0.03)`.
- **Tier 2 (Active/Pressed Bed Tiles, Floating Summary Bars)**: `#FFFFFF`, `border: 1px solid #CBD5E1`, shadow: `0px 4px 6px -1px rgba(15, 23, 42, 0.08), 0px 2px 4px -2px rgba(15, 23, 42, 0.04)`.
- **Tier 3 (Bottom Drawers, Reassignment Sheets)**: `#FFFFFF`, shadow: `0px -4px 16px rgba(15, 23, 42, 0.12)`, topped with backdrop blur overlay `rgba(15, 23, 42, 0.4)`.

### Border Accent Signaling
Bed cards incorporate a `4px` solid directional left accent border corresponding precisely to their current bed status token (`#22C55E`, `#2563EB`, `#D97706`, `#64748B`), allowing rapid peripheral scannability during ward rounds.

## Shapes

The shape system leverages **Rounded (Level 2)** geometry:
- Default elements (inputs, bed tiles, buttons) use `8px` (`0.5rem`) corner radiuses, striking a balance between clinical precision and modern usability.
- Surface containers and bottom sheets employ `16px` (`1rem`) to soften structural bounds.
- Status badges, operational pills, and quick triage counters use fully rounded pill shapes (`9999px`) to immediately distinguish informational tags from interactive rectangular bed cards.

## Components

### Buttons
- **Primary Action (Asignar Cama / Ingreso)**: Solid `#0D5E56` fill, `#FFFFFF` text, `48px` minimum height, `8px` radius. Active state darkens to `#0A4741`.
- **Secondary Action (Cambiar Estatus)**: White background, `1.5px` border with `#0D5E56`, text `#0D5E56`.
- **Destructive Action (Bloquear / Reportar Falla)**: Soft background `#FEE2E2`, border `#FECACA`, text `#DC2626`.
- **Touch Density**: Full-width on mobile modals; compact with icon-left inside patient sheets.

### Bed Status Card (Ficha de Cama)
- **Container**: White surface with `1px solid #E2E8F0` border and a `4px` left status accent border.
- **Top Bar**: Bed number in `numeric-bed` typography on the left; occupancy pill badge on the right.
- **Content Area**: 
  - If occupied: Patient initials or identifier, NSS, triage color dot, and hours elapsed.
  - If dirty: Warning icon with elapsed time in status (*e.g., "1h 24m por desinfectar"*).
  - If available: Clear check icon with positive action label (*"Lista para ingreso"*).

### Service Occupancy Gauge (Barra de Capacidad)
- Compact progress bar with `8px` height and `9999px` border radius.
- Track color: muted neutral (`#E2E8F0`).
- Indicator fill: shifts dynamically based on service threshold (Green `<75%`, Amber `75-84%`, Red `≥85%`).
- Paired with right-aligned bold percentage and fractional count (*e.g., 28/30 Camas*).

### Status Filter Chips (Pills de Filtrado)
- Displayed horizontally in a scrollable header bar.
- Unselected state: `#FFFFFF` surface, `#64748B` label, `1px solid #E2E8F0` outline.
- Selected state: Filled with the respective status tint (e.g., `#DCFCE7` for *Libres*), solid status-colored text (`#16A34A`), and prominent counter indicator (*"Libres (6)"*).

### Patient Banner & Inputs
- **Search & Filter Inputs**: High contrast `#FFFFFF` background, `44px` height, `#0F172A` text, clear reset button. Active focus shows a `2px` ring in institutional teal (`#0D5E56`).
- **NSS / Identification Strip**: Monospaced tabular numeral formatting for Seguro Social / CURP records to prevent character misreading.