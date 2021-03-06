require 'net/http'
require 'uri'
require 'json'
require 'set'
require 'time'

require_relative '../entity/event'
require_relative '../entity/player'
require_relative '../entity/event_set'

# TODO: Hastily factored this out into a class to avoid conflicts with constants. Review this.
class ChallongeClient
    ID_TEMPLATE = "C%s"
    BASE_URL = "https://api.challonge.com/v1/tournaments/"
    MTA_RELEASE_TIME = Time.utc(2018, 6, 22)

    def initialize(api_token)
        @api_token = api_token
    end

    def get_event(event_id)
        event_map = JSON.parse(_query_event(event_id))
        participants_map = JSON.parse(_query_event_participants(event_id))
        matches_map = JSON.parse(_query_event_matches(event_id))

        return _transform_event(event_map, participants_map, matches_map)
    end

    def _query_event(event_id)
        uri = URI(BASE_URL + "%s.json?api_key=%s" % [event_id, @api_token])
        return Net::HTTP.get(uri)
    end

    def _query_event_participants(event_id)
        uri = URI(BASE_URL + "%s/participants.json?api_key=%s" % [event_id, @api_token])
        return Net::HTTP.get(uri)
    end

    def _query_event_matches(event_id)
        uri = URI(BASE_URL + "%s/matches.json?api_key=%s" % [event_id, @api_token])
        return Net::HTTP.get(uri)
    end

    def _generate_player_id_to_name_map(participants_map)
        map = {}

        participants_map.each do |participant_map|
            participant = participant_map["participant"]

            if participant["challonge_username"] != nil
                map[ID_TEMPLATE % participant["id"]] = participant["challonge_username"]
            elsif participant["name"] != nil
                map[ID_TEMPLATE % participant["id"]] = participant["name"]
            end
        end

        return map
    end

    def _transform_event(event_map, participants_map, matches_map)
        player_id_to_name_map = _generate_player_id_to_name_map(participants_map)

        tournament = event_map["tournament"]
        event_start_time = Time.parse(tournament["started_at"])
        event_day_number = (event_start_time - MTA_RELEASE_TIME).to_i / (24 * 60 * 60)

        event_id = ID_TEMPLATE % tournament["id"]
        event_name = tournament["name"]

        event = Event.new(event_id, event_name)
        players = Set.new()
        sets = []

        matches_map.each do |match_map|
            match = match_map["match"]
            player1_id = ID_TEMPLATE % match["player1_id"]
            player2_id = ID_TEMPLATE % match["player2_id"]

            player1_score, player2_score = match["scores_csv"].match(/(-?\d+)-(-?\d+)/).captures()
            player1_score = player1_score.to_i()
            player2_score = player2_score.to_i()

            # Ignore games that have negative scores, i.e. they have not been played out.
            if player1_score < 0 or player2_score < 0
                next
            end

            winner_id = ID_TEMPLATE % match["winner_id"]
            winner = if winner_id == player1_id then
                "B"
            else
                "W"
            end

            sets.push(EventSet.new(event_id, player1_id, player2_id, winner, event_day_number))
            players.add(Player.new(player1_id, player_id_to_name_map[player1_id]))
            players.add(Player.new(player2_id, player_id_to_name_map[player2_id]))
        end

        return event, players, sets
    end
end
