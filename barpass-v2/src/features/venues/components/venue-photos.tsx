interface VenuePhotosProps {
  photoRefs: string[];
}

export function VenuePhotos({ photoRefs }: VenuePhotosProps) {
  if (photoRefs.length === 0) {
    return (
      <div className="rounded-[20px] border border-border-subtle bg-surface p-5 text-sm text-text-secondary">
        Photos will appear here once venue media is available.
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {photoRefs.slice(0, 4).map((ref) => (
        <div key={ref} className="rounded-[20px] border border-border-subtle bg-surface p-4 text-sm text-text-secondary">
          Photo reference: {ref}
        </div>
      ))}
    </div>
  );
}
