type Props = { src: string; alt: string; className?: string; priority?: boolean };

/** A screenshot in a plain phone bezel. The images are 1080x2424 captures. */
export function Phone({ src, alt, className = '', priority = false }: Props) {
  return (
    <figure className={`phone ${className}`}>
      <img
        src={src}
        alt={alt}
        width={1080}
        height={2424}
        loading={priority ? 'eager' : 'lazy'}
        decoding="async"
      />
    </figure>
  );
}
