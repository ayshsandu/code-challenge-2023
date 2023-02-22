import ballerina/http;
import ballerina/jwt;
// import ballerina/log;

# A service representing a network-accessible API
# bound to port `9090`.
service /ecomm on new http:Listener(9090) {

    resource function get items(@http:Header {name: "x-jwt-assertion"} string? authHeader) returns Item[]|ItemWithSubscription[]|error {
        if authHeader != () {
            var jwtTokenPayLoad = check jwt:decode(authHeader);
            var userId = jwtTokenPayLoad[1]["sub"];
            // log:printInfo("[x-jwt-assertion]", userId = userId);
            // string userId = "d772c9f6-2807-4556-ba59-7ca9743428a2";
            if userId != () {
                var userSubscriptions = userSubscriptions.filter(subscription => subscription.userId == userId);
                ItemWithSubscription[] items = from var item in itemTable
                    select {...item, isSubscribed: userSubscriptions.hasKey([userId, item.id])};
                return items;
            }
        }
        return itemTable.toArray();
    }

    resource function post items(@http:Payload Item[] itemEntries)
                                    returns Item[]|ConflictingItemCodesError {

        string[] conflictingIDs = from Item itemEntry in itemEntries
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

    resource function get items/[string id]() returns Item|InvalidItemCodeError {
        Item? itemEntry = itemTable[id];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${id}`
                }
            };
        }
        return itemEntry;
    }

    resource function put items/[string id](@http:Payload Item item) returns Item|InvalidItemCodeError {
        return item;
    }

    // A resource function to get a subscription and add it to the subscription table
    resource function post subscriptions(@http:Payload Subscription subscription) returns InvalidItemCodeError? {

        Item? itemEntry = itemTable[subscription.itemId];
        if itemEntry is () {
            return {
                body: {
                    errmsg: string `Invalid Item Code: ${subscription.itemId}`
                }
            };
        }
        //check whether the subscription is already available
        if userSubscriptions.hasKey([subscription.userId, subscription.itemId]) {
            return {
                body: {
                    errmsg: string `Subscription already exists for Item Code: ${subscription.itemId}`
                }
            };
        }
        userSubscriptions.add(subscription);
        return;
    }
}

public type Item record {|
    readonly string id;
    string imageUrl;
    string title;
    string description;
    decimal price;
    boolean 'isAvailable;
    string includes;
    string intendedFor;
    string color;
    string material;
|};

public type ItemWithSubscription record {|
    *Item;
    boolean isSubscribed;
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

// A type representing user subscription to an item
public type Subscription record {|
    readonly string userId;
    readonly string itemId;
|};

//* a table with sample subscription data as a Subscription record array
public final table<Subscription> key(userId, itemId) userSubscriptions = table [
        {
            userId: "d772c9f6-2807-4556-ba59-7ca9743428a2",
            itemId: "9780743273565"
        }
    ];

public final table<Item> key(id) itemTable = table [
        {
            id: "9780743273565",
            imageUrl: "https://s.yimg.com/lo/api/res/1.2/V04hK2wI1fFem4IFxZXXIQ--/YXBwaWQ9ZWNfaG9yaXpvbnRhbDtoPTQwMDtzcz0xO3c9NDAw/http://s7d6.scene7.com/is/image/PetSmart/5334729.cf.jpg",
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
            imageUrl: "https://m.media-amazon.com/images/I/51zTNwiClXL.jpg",
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
            id: "9781510724542",
            imageUrl: "https://m.media-amazon.com/images/I/71aVxw+AKIL._AC_UF894,1000_QL80_.jpg",
            title: "Pogi's Poop Bags",
            description: "Make cleaning up after your dog a little less unpleasant with Pogi's Poop Bags. Made from high-quality, eco-friendly materials, these bags are strong, leak-proof, and deodorized, ensuring a clean and hygienic pick-up every time. Plus, the bright and colorful design makes them easy to spot in any setting.",
            isAvailable: true,
            price: 12.99,
            includes: "300 Poop Bags",
            intendedFor: "Dog Owners",
            color: "Green, Blue, Purple",
            material: "Biodegradable Plastic"
        }
        // {
        //     id: "9781452151342",
        //     imageUrl: "https://images.squarespace-cdn.com/content/v1/56b27cd486db4396b83ed266/1585343422671-I92GY8S1288YJAGBT7OY/Willow%2Bthe%2BCorgi%2BDog%2BHouse.jpg",
        //     title: "Barkitecture: Designer Dog Houses",
        //     description: "Upgrade your dog's living space with Barkitecture, a stunning collection of designer dog houses. Featuring 20 unique designs from leading architects and designers, this book showcases the latest trends in dog house design, from minimalist modernism to cozy cottage style. It's the perfect inspiration for anyone looking to build or renovate their pup's home.",
        //     isAvailable: true,
        //     price: 29.99,
        //     includes: "1 Hardcover Book",
        //     intendedFor: "Dog Owners",
        //     color: "Multicolor",
        //     material: "Paper"
        // }

    ];

public type ConflictingItemCodesError record {|
    *http:Conflict;
    ErrorMsg body;
|};

public type InvalidItemCodeError record {|
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

// function getUserSubcribedItems(string userId) returns Item[] {
//     var subscriptions = userSubscriptions.filter(s => s.userId == userId);
//     Item[] itemEntries = [];
//     foreach var subscription in subscriptions {
//         Item? itemEntry = itemTable.get(subscription.itemId);
//         if itemEntry is Item {
//             itemEntries.push(itemEntry);
//         }
//     }
//     return itemEntries;
// }