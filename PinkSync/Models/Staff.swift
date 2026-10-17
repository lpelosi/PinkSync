import Foundation

/// Bench staff, mirroring `src/data/staff.ts` on the website. Kept here until
/// the server tracks staff the way it tracks players. A staff member has no
/// stat lines; their page shows the team's record instead.
struct StaffMember: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Title as listed on the roster, e.g. "Head Coach".
    let role: String
    /// Server path for the photo, same scheme as `Player.photoPath`.
    let photoPath: String
    let bio: String

    var photoURL: URL? { URL(string: Secrets.baseURL + photoPath) }

    var lastName: String { name.components(separatedBy: " ").last ?? name }

    static let headCoach = StaffMember(
        id: "coach-brian-perez",
        name: "Brian Perez",
        role: "Head Coach",
        photoPath: "/img/players/coach.jpg",
        bio: "Brian played 12 professional seasons in Mogadishu, Somalia, in a league so elite that nobody has ever found a record of it. His career ended the way all the great ones do, with an arrow to the knee. He retired to a quiet life of whiskey and yelling, then found a team bad enough to need both. His system is simple: he yells, we nod, and then we do whatever we were going to do anyway. The record below is officially his now. He would like it noted that most of it happened before he got here. We would like it noted that he has not said which part."
    )

    /// In the order they are listed on the roster.
    static let all: [StaffMember] = [headCoach]
}
