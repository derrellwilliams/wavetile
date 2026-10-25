import Foundation
import GRDB

/// Cleans up genre tags, which vary a lot between files and taggers.
public enum GenreTag {
    /// Splits combined tags ("Electronic, Classical", "Punk;Rock", "Hip-Hop/Rap") into separate
    /// genres, trims them, and drops label tags ("lbl:ANTI-"). "&" is kept ("R&B", "Funk & Soul").
    public static func split(_ raw: String) -> [String] {
        raw.split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("lbl:") }
    }

    /// SQL for the key that groups spellings of one genre: case-insensitive, hyphens as spaces
    /// ("Hip-Hop" = "hip hop").
    static func keySQL(_ column: String) -> String {
        "lower(replace(\(column), '-', ' '))"
    }
}

public extension LibraryDatabase {
    /// One row per genre, merging spellings that differ only in case or hyphens. Each shows its
    /// capitalized spelling (most common first) and the number of distinct albums.
    func genres() -> ValueObservation<ValueReducers.Fetch<[GenreSummary]>> {
        let key = GenreTag.keySQL("genre")
        return ValueObservation.tracking { db in
            try GenreSummary.fetchAll(db, sql: """
                WITH spelling AS (
                    SELECT \(key) AS k, genre, COUNT(*) AS n FROM albumGenre GROUP BY genre
                ), ranked AS (
                    SELECT k, genre, ROW_NUMBER() OVER (
                        PARTITION BY k ORDER BY unicode(genre) BETWEEN 65 AND 90 DESC, n DESC, genre
                    ) AS r FROM spelling
                ), counts AS (
                    SELECT \(key) AS k, COUNT(DISTINCT albumID) AS albumCount FROM albumGenre GROUP BY k
                )
                SELECT ranked.genre AS genre, counts.albumCount AS albumCount
                FROM ranked JOIN counts USING (k)
                WHERE r = 1
                ORDER BY genre COLLATE NOCASE
                """)
        }
    }

    /// Albums tagged with any spelling of `genre`.
    func albums(genre: String) -> ValueObservation<ValueReducers.Fetch<[AlbumRecord]>> {
        let key = GenreTag.keySQL("albumGenre.genre")
        return ValueObservation.tracking { db in
            try AlbumRecord.fetchAll(db, sql: """
                SELECT DISTINCT album.* FROM album
                JOIN albumGenre ON albumGenre.albumID = album.id
                WHERE \(key) = \(GenreTag.keySQL("?"))
                ORDER BY album.sortTitle
                """, arguments: [genre])
        }
    }
}
