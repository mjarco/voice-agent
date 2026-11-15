import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:voice_agent/core/theme/app_colors.dart';

/// Aurora's glass (off-roadmap S2, 2026-11-15-va-graphite-glass): the
/// shapes the owner liked in the research (drafts/10 §3), measured in dp as
/// in the mockups (`AUR_CSS` of drafts/assets/mockups_dynamic.py).
///
/// A surface either blurs what is behind it ([blur], a `BackdropFilter`) or
/// lays a translucent fill over it. Cards sit on the soft sky, where a blur
/// changes almost nothing, so they do not blur; the floating input and the
/// tab bar have the list scrolling under them, so they do (D11 of S2: Dziś
/// scrolled on the Pixel at 120 Hz with under 1% of frames late).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.blur = false,
    this.fill,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool blur;

  /// Instead of the theme's glass fill (a tint, a warning).
  final Color? fill;
  final bool shadow;

  /// The blur of a frosted surface, as CSS `blur(22px)`.
  static const sigma = 22.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shape = BorderRadius.circular(radius);
    // Without the blur the fill carries the frost alone, so it is denser.
    final base =
        fill ??
        (blur
            ? colors.glassFill
            : Color.alphaBlend(
                colors.glassFill,
                colors.background.withValues(alpha: 0.22),
              ));
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: shape,
        border: Border.all(color: colors.glassLine),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (blur) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: body,
      );
    }
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: shadow
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Material(type: MaterialType.transparency, child: body),
        ),
      ),
    );
  }
}

/// A frosted card: radius 28, the page's side margin of 16.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.fill,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 28,
      margin: margin,
      fill: fill,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Rows on one card, split by hairlines (radius 24).
class GlassList extends StatelessWidget {
  const GlassList({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final line = AppColors.of(context).glassLine;
    return GlassSurface(
      margin: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: line),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A row of a [GlassList]: an optional leading pill, the text, a note.
class GlassRow extends StatelessWidget {
  const GlassRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.done = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Struck through and muted, as a ticked task.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      color: done ? muted : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontSize: 12,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: muted, size: 20),
                  child: trailing!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pill: a time, a count, a state; the warning's when [warning].
class GlassPill extends StatelessWidget {
  const GlassPill(
    this.text, {
    super.key,
    this.warning = false,
    this.minWidth = 54,
  });

  final String text;
  final bool warning;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: warning ? colors.warning : colors.chip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: warning ? colors.onWarning : null,
        ),
      ),
    );
  }
}

/// A round glass button of 42 dp: the app bar's actions.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 42,
      height: 42,
      child: GlassSurface(
        radius: 21,
        shadow: false,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          // A button with nothing to do fades, as Material's disabled one.
          child: Center(
            child: Opacity(
              opacity: onPressed == null ? 0.35 : 1,
              child: Icon(icon, size: 22),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The small caps over a block: "AGENDA".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The floating tab bar: a glass pill of 60 dp, 30 dp from the sides and 16
/// from the bottom, icons only (the cut's item 2, answer a); the current tab
/// in a dark pill. [bar] is Material's `NavigationBar`, which keeps its
/// labels for TalkBack and tooltips; this only gives it Aurora's shape.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.bar});

  final NavigationBar bar;

  static const height = 60.0;
  static const bottomGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        30,
        0,
        30,
        bottomGap + MediaQuery.paddingOf(context).bottom,
      ),
      child: GlassSurface(
        key: const Key('glass-tab-bar'),
        radius: height / 2,
        blur: true,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: height,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              indicatorColor: scheme.onSurface,
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(21),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? scheme.surface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            child: bar,
          ),
        ),
      ),
    );
  }
}
