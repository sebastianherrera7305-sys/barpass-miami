import type { LiveReview } from "@/types";

interface VenueReviewsProps {
  rating: number;
  reviewCount: number;
  reviews: LiveReview[];
}

export function VenueReviews({ rating, reviewCount, reviews }: VenueReviewsProps) {
  return (
    <div className="rounded-[20px] border border-border-subtle bg-surface p-5">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-bold">Reviews</h3>
        <span className="text-sm text-amber-brand">{rating} • {reviewCount}</span>
      </div>
      {reviews.length === 0 ? (
        <p className="text-sm text-text-secondary">No verified reviews available yet.</p>
      ) : (
        <div className="space-y-3">
          {reviews.slice(0, 3).map((review, index) => (
            <div key={`${review.author}-${index}`} className="rounded-[16px] border border-border-subtle/70 bg-surface-raised p-3">
              <p className="text-sm font-semibold text-white">{review.author}</p>
              <p className="mt-1 text-sm text-text-secondary">{review.text}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
