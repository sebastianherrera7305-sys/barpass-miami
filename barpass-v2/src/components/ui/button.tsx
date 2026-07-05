import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";
import { forwardRef, type ButtonHTMLAttributes } from "react";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 font-semibold transition-all duration-200 disabled:opacity-40 disabled:pointer-events-none focus-visible:outline-2 focus-visible:outline-amber-brand",
  {
    variants: {
      variant: {
        primary:
          "bg-gradient-to-r from-amber-brand to-amber-bright text-black hover:brightness-110 active:scale-[0.98] glow-amber",
        secondary:
          "bg-surface-raised text-white border border-border-subtle hover:bg-surface-overlay",
        ghost: "text-white/60 hover:text-white hover:bg-white/5",
        outline:
          "border border-amber-brand/40 text-amber-brand hover:bg-amber-brand/10",
      },
      size: {
        sm: "h-9 px-4 text-sm rounded-[12px]",
        md: "h-11 px-6 text-[15px] rounded-[14px]",
        lg: "h-13 px-8 text-base rounded-[16px]",
      },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => (
    <button
      ref={ref}
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  ),
);
Button.displayName = "Button";
