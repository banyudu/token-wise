import { type ReactNode, type ReactElement, cloneElement, useRef, useState, useLayoutEffect, useEffect, useCallback } from "react";
import { createPortal } from "react-dom";

interface TooltipProps {
  content: ReactNode;
  children: ReactElement<Record<string, unknown>>;
  delay?: number;
}

export function Tooltip({ content, children, delay = 200 }: TooltipProps) {
  const triggerRef = useRef<HTMLElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const hideTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [visible, setVisible] = useState(false);
  const [pos, setPos] = useState<{ top: number; left: number; above: boolean }>({ top: 0, left: 0, above: true });

  const updatePosition = useCallback(() => {
    const trigger = triggerRef.current;
    const tooltip = tooltipRef.current;
    if (!trigger || !tooltip) return;

    const rect = trigger.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();
    const gap = 8;

    const above = rect.top > tooltipRect.height + gap;
    const top = above ? rect.top - gap : rect.bottom + gap;
    const left = Math.max(8, Math.min(rect.left + rect.width / 2 - tooltipRect.width / 2, window.innerWidth - tooltipRect.width - 8));

    setPos({ top, left, above });
  }, []);

  useLayoutEffect(() => {
    if (visible) updatePosition();
  }, [visible, updatePosition]);

  useEffect(() => {
    return () => {
      clearTimeout(timerRef.current);
      clearTimeout(hideTimerRef.current);
    };
  }, []);

  const cancelHide = () => {
    clearTimeout(hideTimerRef.current);
  };

  const show = () => {
    cancelHide();
    timerRef.current = setTimeout(() => setVisible(true), delay);
  };

  const hide = () => {
    clearTimeout(timerRef.current);
    hideTimerRef.current = setTimeout(() => setVisible(false), 100);
  };

  if (!content) return children;

  return (
    <>
      {cloneElement(children, {
        ref: triggerRef,
        onMouseEnter: (e: React.MouseEvent) => { show(); (children.props as any).onMouseEnter?.(e); },
        onMouseLeave: (e: React.MouseEvent) => { hide(); (children.props as any).onMouseLeave?.(e); },
      })}
      {visible &&
        createPortal(
          <div
            ref={tooltipRef}
            role="tooltip"
            className={`tooltip-portal ${pos.above ? "tooltip-above" : "tooltip-below"}`}
            style={{ top: pos.top, left: pos.left }}
            onMouseEnter={cancelHide}
            onMouseLeave={hide}
          >
            {content}
          </div>,
          document.body
        )}
    </>
  );
}

export function TruncatedCell({ content, children, className }: { content: ReactNode; children: ReactNode; className?: string }) {
  return (
    <Tooltip content={content}>
      <span className={`block truncate ${className ?? ""}`}>{children}</span>
    </Tooltip>
  );
}
