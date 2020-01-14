class CfaccsController < ApplicationController
	http_basic_authenticate_with name: "trinhxhai", password: "sn1892000", except: [:index, :show,:create,]
	require 'date'
	def index
		@cfaccs = Cfacc.all

		@cnt_acpt_hash={}

		@cfaccs.each do |acc|
			cnt = 0
			acc.submissions.each do |sub|
				if sub[:subaccs]>0 
					cnt+=1
				end
			end
			@cnt_acpt_hash[acc[:id]]=cnt
		end

	end
	def new
		@cfacc = Cfacc.new
	end
	def create
		@cfacc = Cfacc.new(cfacc_params)

		RestClient.get "https://codeforces.com/api/user.info?handles=#{@cfacc[:username]}" do |response,request,result| 

			if 	JSON.parse(response)["status"]=="FAILED"
				 @cfacc.errors[:base] << "Username doesn't not exist !"
				 render 'new'
			else
				res = JSON.parse(response)["result"][0]
				@cfacc[:rating] = res["rating"].to_i
				@cfacc[:m_rating] = res["maxRating"]
				@cfacc[:rank] = res["rank"]
				@cfacc[:m_rank] = res["maxRank"]
				@cfacc.save

				taking_contest @cfacc[:id]
				taking_submission @cfacc[:id]
				redirect_to @cfacc
			end
		end

	end
	def show
		@cfacc = Cfacc.find(params[:id])
		@analy_aw = analy_accs_wrongs @cfacc.analies
		#@analy_tags = analu_tags @cfacc.analies
		#@maxRatingProb = maxRatingProb @cfacc.submissions
		
	end
	def edit
		@cfacc = Cfacc.find(params[:id])
	end

	def update

		@cfacc = Cfacc.find(params[:id])
		#dawfawd
		notsame = @cfacc[:username]!=params["cfacc"]["username"]
		RestClient.get "https://codeforces.com/api/user.info?handles=#{params["cfacc"]["username"]}" do |response,request,result| 

			if 	JSON.parse(response)["status"]=="FAILED"
				 @cfacc.errors[:base] << "Username doesn't not exist !"
				 render 'edit'
			else
				res = JSON.parse(response)["result"][0]
				@cfacc[:username]= params["cfacc"]["username"]
				@cfacc[:realname]=params["cfacc"]["realname"]
				@cfacc[:rating] = res["rating"].to_i
				@cfacc[:m_rating] = res["maxRating"]
				@cfacc[:rank] = res["rank"]
				@cfacc[:m_rank] = res["maxRank"]
				@cfacc.save
				if notsame 
					@cfacc.contests.destroy_all
					@cfacc.submissions.destroy_all
					@cfacc.analies.destroy_all
				end
				taking_contest @cfacc[:id]
				taking_submission @cfacc[:id]
				redirect_to @cfacc
			end
		end


	end
	def destroy
		@cfacc = Cfacc.find(params[:id])
		@cfacc.destroy
		redirect_to cfaccs_path
	end
	def load
		listacc = Cfacc.all
		#reload all acc info
		tanking_info listacc

		listacc.each do |acc|
			id = acc[:id]
			lastContestId = nil
			if acc.contests.length!=0
				lastContestId = acc.contests[0][:contestId]
			end
			taking_contest id
			taking_submission id
		end
		redirect_to cfaccs_path
	end	
	private
		def cfacc_params
			params.require(:cfacc).permit(:username,:realname)
		end
		def tanking_info listacc 
			listname = ""
			arr_id =[]
			listacc.each do |acc|
				listname+= "#{acc[:username]};"
				arr_id << acc
			end

			arr_info = JSON.parse(RestClient.get "https://codeforces.com/api/user.info?handles=#{listname[0..listname.length-2]}" )["result"]
			i = 0
			arr_info.each do |user_info| 
				@acc = Cfacc.find(listacc[i][:id])
				@acc[:rating] = user_info["rating"]
				@acc[:m_rating] =user_info["maxRating"]
				@acc[:rank]= user_info["rank"]
				@acc[:m_rank]= user_info["maxRank"]
				@acc.save
				#1+6+72+a
				i+=1
			end

		end
		def taking_contest  id
			cfacc = Cfacc.find(id)
			

			lastContestId  = nil
			if ! cfacc.contests[0].nil?
				lastContestId  = cfacc.contests[0][:contestId].to_i
			end
			contests =[]
			contests = JSON.parse(RestClient.get "https://codeforces.com/api/user.rating?handle=#{cfacc[:username]}" )["result"]
			contests.each do |contest|
				if contest["contestId"] == lastContestId
					break
				else
				cfacc.contests.create({
					:contestId=>contest["contestId"], 
					:contestName => contest["contestName"],
					:rank => contest["rank"], 
					:oldRating => contest["oldRating"], 
					:newRating => contest["newRating"]})
				end
			end
		end
		def taking_submission id
			cfacc = Cfacc.find(id)
			lastIdSub = nil
			if !cfacc.submissions[0].nil?
				lastIdSub = cfacc.submissions[0][:sub_id].to_i
			end
			
			submissions =[]
			submissions	= JSON.parse(RestClient.get("https://codeforces.com/api/user.status?handle=#{cfacc[:username]}&from=1&count=100000"))["result"]
			cnt_hash = {}
			info_hash={}
			submissions.each do |sub|
				if sub["id"]==lastIdSub
					break
				end
				#Analysis info
				cfacc.analies.create({
						:sub_id => sub["id"],
						:timestamp => sub["creationTimeSeconds"],
						:b_acc => (sub["verdict"]=="OK"),
						:tags =>sub["problem"]["tags"].join(';'),
						:rating =>sub["problem"]["rating"]
					})					

				#Analysis info
				if cnt_hash[ sub["contestId"] ] == nil
					cnt_hash[ sub["contestId"] ] = { sub["problem"]["index"] => [0,0]}

				else
					cnt_hash[ sub["contestId"] ][ sub["problem"]["index"] ] = [0,0]
				end

				if info_hash[ sub["contestId"] ] == nil
					info_hash[ sub["contestId"] ] = {
						sub["problem"]["index"] => {
							:sub_id => sub["id"],
							:name => sub["problem"]["name"],
							:rating => sub["problem"]["rating"]
						} 
					}

				else
					info_hash[ sub["contestId"] ][ sub["problem"]["index"] ] = {
						:sub_id => sub["id"],
						:name => sub["problem"]["name"],
						:rating => sub["problem"]["rating"]
					}
				end
			end
			submissions.each do |sub|
				if sub["id"]==lastIdSub
					break
				end
				if sub["verdict"] == "OK"
					cnt_hash[ sub["contestId"] ][ sub["problem"]["index"] ][1] +=1
				else
					cnt_hash[ sub["contestId"] ][ sub["problem"]["index"] ][0] +=1
				end
			end

			info_hash.keys.each do |contest|
				info_hash[contest].keys.each do |idx|
					cfacc.submissions.create({
						:contestId => contest,
						:prob_index => idx,
						:sub_id =>info_hash[contest][idx][:sub_id],
						:prob_name => info_hash[contest][idx][:name],
						:prob_rating => info_hash[contest][idx][:rating],
						:subaccs =>cnt_hash[contest][idx][1],
						:subwrongs =>cnt_hash[contest][idx][0],
					})

				end
			end

		end
		def analy_accs_wrongs  analies
			res = {}

			analies.each do |sub| 

				t = DateTime.strptime(sub[:timestamp].to_s,'%s')
				
				y = t.year.to_s
				m = t.month.to_s

				acc=0
				wrog=0

				if sub[:b_acc] 
					acc=1
				else
					wrog=1
				end  
				
				if res[y].nil?
					res[y]={m=>[acc,wrog]}
				else
					if res[y][m].nil?
						res[y][m]=[acc,wrog]
					else
						res[y][m]=[ res[y][m][0]+acc , res[y][m][1]+wrog ]
					end
				end
			end
			return res

		end
		def analu_tags analies
			res = {}
			analies.each do |sub| 

				if sub[:b_acc] 
						s = sub[:tags]
						s.split(';').each do |tag|
							if res[tag].nil?								
								res[tag]=0
							else
								res[tag]=res[tag]+1
							end
						end
				end  
			end

			return res	
		end
		def maxRatingProb submissions
			max = 0
			submissions.each do |sub|
				if !sub[:prob_rating].nil?
				if sub[:subaccs]>0 && sub[:prob_rating]> max 
						max = sub[:prob_rating]
				end
				end
			end
			return max
		end
end
