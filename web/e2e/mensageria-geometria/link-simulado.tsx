// Substitui next/link no harness (sem roteador do Next).
export default function Link({ href, children, ...rest }: { href: string; children: React.ReactNode } & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  return <a href={href} {...rest}>{children}</a>;
}
