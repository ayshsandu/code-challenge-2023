import ballerina/http;

# A service representing a network-accessible API
# bound to port `9090`.
service /ecomm on new http:Listener(9090) {

    resource function get items() returns ItemEntry[] {
        return itemTable.toArray();
    }

    resource function post items(@http:Payload ItemEntry[] itemEntries)
                                    returns ItemEntry[]|ConflictingItemCodesError {

        string[] conflictingIDs = from ItemEntry itemEntry in itemEntries
            where itemTable.hasKey(itemEntry.id)
            select itemEntry.id;

        if conflictingIDs.length() > 0 {
            return {
                body: {
                    errmsg: string:'join(" ", "Conflicting Item Codes:", ...conflictingIDs)
                }
            };
        } else {
            foreach var itemEntry in itemEntries {
                itemEntry.isAvailable = true;
                itemTable.add(itemEntry);
            }
            return itemEntries;
        }
    }

    resource function get items/[string id]() returns ItemEntry|InvalidISBNCodeError {
        ItemEntry? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${id}`
                }
            };
        }
        return itemEntry;
    }

    resource function put items/[string id]/actions(@http:Payload MemberAction memberAction) returns ItemEntry|InvalidISBNCodeError {
        ItemEntry? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid ISBN Code: ${id}`
                }
            };
        } else {
            if memberAction.action == "borrow" {
                if (!itemEntry.'isAvailable) {
                    return {
                        body: {
                            errmsg: string `Book is not available to borrow: ${id}`
                        }
                    };
                }

                if (!customers.hasKey(memberAction.memberId) || customers.get(memberAction.memberId).length() == 0) {
                    customers[memberAction.memberId] = {items: [id]};
                } else {
                    customers.get(memberAction.memberId).items.push(id);
                }
                itemEntry.isAvailable = false;
                return itemEntry;
            } else if memberAction.action == "return" {
                if (!customers.hasKey(memberAction.memberId) || customers.get(memberAction.memberId).length() == 0) {
                    return {
                        body: {
                            errmsg: string `Book is not borrowed by : ${memberAction.memberId}`
                        }
                    };
                } else {
                    Reader borrower = customers.get(memberAction.memberId);
                    customers[memberAction.memberId].items = borrower.items.filter(i => i != id);
                    itemEntry.isAvailable = true;
                    return itemEntry;
                }
            } else {
                return {
                    body: {
                        errmsg: string `Invalid Action: ${memberAction.action}`
                    }
                };
            }
        }
    }
}

public type ItemEntry record {|
    readonly string id;
    string title;
    string description;
    decimal price;
    boolean 'isAvailable;
    string includes;
    string intendedFor;
    string color;
    string material;
|};

public type Address record {|
    string city;
    string street;
    string postalcode;
    string locationLink;
|};

public type Reader record {|
    string[] items;
|};

public type MemberAction record {|
    string action;
    string memberId;
|};

public final table<ItemEntry> key(id) itemTable = table [
        {
            id: "9780743273565",
            title: "Top Paw® Valentine's Day Single Dog Sweater",
            description: "Dress your pup up appropriately for Valentine's Day with this Top Paw Valentine's Day Kisses Dog Sweater. This sweet sweater slips on and off easily while offering a comfortable fit, and lets it be known that your pup is single and ready to mingle",
            isAvailable: true,
            price: 5.0,
            includes: "1 Sweater",
            intendedFor: "Small Dogs",
            color: "Red",
            material: "Cotton"
        },
        {
            id: "9781623363586",
            title: "PetSafe® Automatic Ball Launcher",
            description: "Keep your furry friend entertained for hours with the PetSafe Automatic Ball Launcher. This interactive toy launches standard-sized tennis balls up to 30 feet away, allowing your dog to chase and retrieve them without any effort from you. With multiple safety sensors and automatic rest periods, it's the perfect toy for energetic dogs who need a little extra exercise.",
            isAvailable: true,
            price: 150.0,
            includes: "1 Automatic Ball Launcher, 3 Tennis Balls",
            intendedFor: "Medium to Large Dogs",
            color: "Purple,Grey",
            material: "Plastic"
        },
        {
            id: "9781452151342",
            title: "Barkitecture: Designer Dog Houses",
            description: "Upgrade your dog's living space with Barkitecture, a stunning collection of designer dog houses. Featuring 20 unique designs from leading architects and designers, this book showcases the latest trends in dog house design, from minimalist modernism to cozy cottage style. It's the perfect inspiration for anyone looking to build or renovate their pup's home.",
            isAvailable: true,
            price: 29.99,
            includes: "1 Hardcover Book",
            intendedFor: "Dog Owners",
            color: "Multicolor",
            material: "Paper"
        },
        {
            id: "9781510724542",
            title: "Pogi's Poop Bags",
            description: "Make cleaning up after your dog a little less unpleasant with Pogi's Poop Bags. Made from high-quality, eco-friendly materials, these bags are strong, leak-proof, and deodorized, ensuring a clean and hygienic pick-up every time. Plus, the bright and colorful design makes them easy to spot in any setting.",
            isAvailable: true,
            price: 12.99,
            includes: "300 Poop Bags",
            intendedFor: "Dog Owners",
            color: "Green, Blue, Purple",
            material: "Biodegradable Plastic"
        }
    ];

public final map<Reader> customers = {
    "00001": {items: ["9780141439518"]}
};

public type ConflictingItemCodesError record {|
    *http:Conflict;
    ErrorMsg body;
|};

public type InvalidISBNCodeError record {|
    *http:NotFound;
    ErrorMsg body;
|};

public type BookIsnotAvailable record {|
    *http:Forbidden;
    ErrorMsg body;
|};

public type ErrorMsg record {|
    string errmsg;
|};

